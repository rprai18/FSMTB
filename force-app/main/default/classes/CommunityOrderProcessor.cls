public without sharing class CommunityOrderProcessor {
	private final static Integer CE_MEMBERSHIP_DURATION = 12;
	private static Map<String, PurchaseType> pTypeMap = new Map<String, PurchaseType> {
		'cer-course' => PurchaseType.CE_COURSE,
		'cer-feedback' => PurchaseType.CE_FEEDBACK,
		'cer-membership' => PurchaseType.CE_MEMBERSHIP,
		'cer-membership-renewal' => PurchaseType.CE_RENEWAL,
		'mlvc-membership-1-month' => PurchaseType.MLVC_MEMBERSHIP,
		'mlvc-membership-3-month' => PurchaseType.MLVC_MEMBERSHIP,
		'mlvc-membership-6-month' => PurchaseType.MLVC_MEMBERSHIP,
		'mlvc-membership-12-month' => PurchaseType.MLVC_MEMBERSHIP
	};
	private static Map<PurchaseType, String> emailTemplateMap = new Map<PurchaseType, String> {
		PurchaseType.CE_FEEDBACK => 'CE_Survey_Feedback_Purchase_Confirmation',
		PurchaseType.CE_MEMBERSHIP => 'Membership_Purchase_Confirmation',
		PurchaseType.CE_RENEWAL => 'Membership_Purchase_Confirmation',
		PurchaseType.MLVC_MEMBERSHIP => 'Membership_Purchase_Confirmation'
	};
	private static User owner;
	// Store email status for debugging (visible in console logs)
	public static String emailStatusMessage = '';
	public static String userCreatedId = '';
	public static String emailSentTo = '';
	public static String createdUserId = ''; // Store User ID for console logging


	public static PurchaseType getPurchaseType(Id orderId) {
		List<OrderItem> orderItems = [SELECT Product2.ProductCode FROM OrderItem WHERE OrderId = :orderId LIMIT 1];
		if (orderItems.isEmpty()) {
			return null;
		}
		String productCode = orderItems[0].Product2.ProductCode;
		return pTypeMap.get(productCode);
	}

	public static PageReference processOrders(Id accountId, Id contactId, List<Order> orders, String transactionId) {
		// Reset static variables at the start of each payment processing
		// This ensures we don't have stale data from previous transactions
		emailStatusMessage = '';
		userCreatedId = '';
		emailSentTo = '';
		owner = null;
		
		PageReference pageRef;
		Boolean success = true;//TODO what is the point of this???
        String strbody ='Thank you for submitting your course to the FSMTB CE Registry.<br><br>';
		strbody += 'This automated email serves as your receipt. Note: Please do not reply to this email, as this is not a monitored email account.<br><br>';
        strbody += 'Course Registration Order Details:<br><br>';
        List<Account> accountList = [SELECT Name FROM Account WHERE Id = :accountId LIMIT 1];
        if (accountList.isEmpty()) {
            throw new QueryException('Account not found with ID: ' + accountId);
        }
        String accName = accountList[0].Name;

		List<OrderItem> orderItems = new List<OrderItem>();

		// NOTE: Cannot use SavePoint/rollback here because payment callout happens BEFORE this method is called
		// Salesforce doesn't allow rollback after a callout. Handle errors gracefully instead.
		if (success) {
			for (Order order : orders) {
				PurchaseType pType = null;
				if (order.OrderItems != null && !order.OrderItems.isEmpty() && order.OrderItems[0].Product2 != null) {
					pType = pTypeMap.get(order.OrderItems[0].Product2.ProductCode);
				}
				
				// CRITICAL: Get and preserve the Order's AccountId FIRST - before doing anything else
				// Query the Order from database to get the AccountId that was set during registration
				List<Order> orderQuery = [SELECT Id, AccountId, Lead__c FROM Order WHERE Id = :order.Id LIMIT 1];
				Id originalAccountId = null;
				if (!orderQuery.isEmpty()) {
					originalAccountId = orderQuery[0].AccountId;
					System.debug('✅✅✅ PRESERVED Order.AccountId from database: ' + originalAccountId);
				} else {
					originalAccountId = order.AccountId; // Fallback to order object value
					System.debug('⚠️ Could not query Order - using AccountId from order object: ' + originalAccountId);
				}
				
				// DO NOT modify the order object - we'll create a new one for update

				for (OrderItem oi :  order.OrderItems) {
					if (oi.Product2 == null || String.isBlank(oi.Product2.ProductCode)) {
						System.debug('WARNING: OrderItem ' + oi.Id + ' has no Product2 or ProductCode');
						continue;
					}

                    pType = pTypeMap.get(oi.Product2.ProductCode);
					System.debug('Processing OrderItem ' + oi.Id + ' with ProductCode: ' + oi.Product2.ProductCode + ', PurchaseType: ' + pType);
					
					// IMPORTANT: Renewal should ONLY happen when explicitly triggered from Account Administration
					// For all other cases (new registrations), treat as new membership
					// Query Order with Lead__c to check if it's a new registration
					List<Order> ordersWithLead = [SELECT Id, Lead__c, AccountId FROM Order WHERE Id = :order.Id LIMIT 1];
					Boolean hasLead = false;
					if (!ordersWithLead.isEmpty()) {
						hasLead = ordersWithLead[0].Lead__c != null;
						System.debug('===== ORDER PROCESSING DECISION =====');
						System.debug('Order.Id: ' + order.Id);
						System.debug('Order.Lead__c (from query): ' + ordersWithLead[0].Lead__c);
						System.debug('Order.AccountId (from query): ' + ordersWithLead[0].AccountId);
						System.debug('ProductCode: ' + oi.Product2.ProductCode);
						System.debug('PurchaseType: ' + pType);
						System.debug('hasLead: ' + hasLead);
					} else {
						System.debug('⚠️ WARNING: Could not query Order to check Lead__c');
						// Fallback: check the order object directly (might not have Lead__c if not queried)
						hasLead = order.Lead__c != null;
						System.debug('Fallback check - order.Lead__c: ' + order.Lead__c);
					}
					
					if (pType == PurchaseType.CE_FEEDBACK) {
						pageRef = Page.CEDownloadFeedback;
					} else if (pType == PurchaseType.CE_RENEWAL && !hasLead) {
						// ONLY treat as renewal if:
						// 1. ProductCode is 'cer-membership-renewal' (from Account Administration renewal button)
						// 2. AND Order has NO Lead__c (not a new registration)
						System.debug('✓ Renewal flow: ProductCode is "cer-membership-renewal" and no Lead__c');
						System.debug('Calling processCerRenewal for OrderItem ' + oi.Id + ' with AccountId: ' + accountId);
						// Set email status to indicate this is a renewal (no new user created)
						emailStatusMessage = 'INFO: This is a renewal payment. No new user created.';
						userCreatedId = '';
						emailSentTo = '';
						try {
							processCerRenewal(oi, accountId);
							System.debug('Successfully processed renewal for OrderItem ' + oi.Id);
						} catch (Exception e) {
							System.debug('ERROR in processCerRenewal: ' + e.getMessage());
							System.debug('Stack trace: ' + e.getStackTraceString());
							throw e; // Re-throw to fail the transaction
						}
						orderItems.add(oi);
						pageRef = Page.PaymentConfirmation;
					} else if (pType == PurchaseType.CE_MEMBERSHIP || (pType == PurchaseType.CE_RENEWAL && hasLead)) {
						// Treat as NEW MEMBERSHIP if:
						// 1. ProductCode is 'cer-membership' (new registration), OR
						// 2. ProductCode is 'cer-membership-renewal' BUT Order has a Lead__c (shouldn't happen, but handle it)
						if (pType == PurchaseType.CE_RENEWAL && hasLead) {
							System.debug('⚠️ ProductCode is "cer-membership-renewal" but Order has Lead__c. Treating as NEW MEMBERSHIP (not renewal).');
						} else {
							System.debug('✓ New registration flow: ProductCode is "cer-membership"');
						}
						// Membership and User creation will be handled by @future method called from payment controller
						// after payment transaction completes (see CeCommunityPaymentLwcController.submitPayment)
						System.debug('OrderItem ' + oi.Id + ' processed - Membership and User will be created asynchronously');
						
						orderItems.add(oi);
						pageRef = Page.PaymentConfirmation;
					} else if (pType == PurchaseType.CE_COURSE) {
						Course__c c = processCourse(oi);
						orderItems.add(oi);

						if (c.Category__c == 'Other') {
							pageRef = Page.CECourseManagement;
							pageRef.getParameters().put('pendingReview', 'yes');
						} else {
                            strbody += 'Course Name: ' + oi.Course_Name__c;
                            strbody += '<br>Course ID: ' + oi.Course__r.name;
                            strbody += '<br>Account: ' + accName;
                            strbody += '<br>Purchase Date: ' +  date.today().format() ;
                            strbody += '<br>Transaction ID: ' + transactionId ;
                            strbody += '<br>Cost: ' + order.TotalAmount;
							pageRef = Page.CESession;
							pageRef.getParameters().put('courseId', c.Id);
							pageRef.getParameters().put('method', 'Add');
							pageRef.getParameters().put('previousPage', 'CEAddCourse');
						}
					}

					//TODO this is changing in a future phase and have been told to leave it be for now (23 April 2018) by Brenna
					else if (pType == PurchaseType.MLVC_MEMBERSHIP) {
						processMlvcMembership(oi, accountId);
					}
				}

                // CRITICAL: Update Order with ONLY the fields we need, explicitly preserving AccountId
                // Create a new Order object with ONLY the fields to update - this prevents any other fields from being changed
                Order orderToUpdate = new Order();
                orderToUpdate.Id = order.Id;
                orderToUpdate.Status = 'Complete';
                orderToUpdate.Transaction_Id__c = transactionId;
                orderToUpdate.Lead__c = null;
                
                // EXPLICITLY set the AccountId to the one we preserved from the start
                if (originalAccountId != null) {
                    orderToUpdate.AccountId = originalAccountId;
                    System.debug('✅✅✅ EXPLICITLY setting Order.AccountId to preserved value: ' + originalAccountId);
                } else {
                    // If we couldn't get it, use the one from the order object
                    orderToUpdate.AccountId = order.AccountId;
                    System.debug('⚠️ Using Order.AccountId from order object: ' + order.AccountId);
                }
                
                // Update ONLY this Order object - no other fields will be touched
				Database.SaveResult updateResult = Database.update(orderToUpdate, false);
				
				if (updateResult.isSuccess()) {
					System.debug('✅ Order update successful');
					// Verify the AccountId was preserved after update
					if (originalAccountId != null) {
						List<Order> verifyOrder = [SELECT Id, AccountId FROM Order WHERE Id = :order.Id LIMIT 1];
						if (!verifyOrder.isEmpty()) {
							if (verifyOrder[0].AccountId == originalAccountId) {
								System.debug('✅✅✅ SUCCESS: Order.AccountId preserved correctly: ' + verifyOrder[0].AccountId);
							} else {
								System.debug('❌❌❌ ERROR: Order.AccountId was changed! Expected: ' + originalAccountId + ', Got: ' + verifyOrder[0].AccountId);
							}
						}
					}
				} else {
					System.debug('❌ Order update failed:');
					for (Database.Error err : updateResult.getErrors()) {
						System.debug('  Error: ' + err.getMessage());
					}
				}

                if (pType == PurchaseType.CE_COURSE) {
                	strbody += '<br><br>If you have any questions, please email FSMTB at CE@fsmtb.org or learn more at www.fsmtb.org.<br><br>Thank you,<br>FSMTB Service Team';
					CommunityUtil.sendCeCourseEmail(strbody, order.Id);
                } else {
                    // Get a valid User ID for email sending
                    // For renewals, owner is null, so we need to find a valid User ID
                    Id targetUserId = owner != null ? owner.Id : getValidUserIdForEmail(accountId);
                    String emailTemplateName = emailTemplateMap.get(pType);
                    if (targetUserId != null && String.isNotBlank(emailTemplateName)) {
                        try {
                            CommunityUtil.sendEmail(targetUserId, emailTemplateName, order.Id);
                        } catch (Exception emailException) {
                            // Log email error but don't fail the payment
                            System.debug('Email sending failed: ' + emailException.getMessage());
                            // Optionally create an error record
                            try {
                                insert new Credit_Card_Error__c(
                                    Error_Text__c = 'Email sending failed for Order ' + order.Id + ': ' + emailException.getMessage()
                                );
                            } catch (Exception e) {
                                System.debug('Could not create error record: ' + e.getMessage());
                            }
                        }
                    } else {
                        System.debug('Cannot send email: targetUserId=' + targetUserId + ', emailTemplateName=' + emailTemplateName);
                    }
                }
			}

			// Update OrderItems with partial success allowed (allOrNone=false)
			// Cannot rollback after callout, so handle errors gracefully
			if (!orderItems.isEmpty()) {
				List<Database.SaveResult> updateResults = Database.update(orderItems, false);
				Boolean hasErrors = false;
				for (Database.SaveResult result : updateResults) {
					if (!result.isSuccess()) {
						hasErrors = true;
						for (Database.Error err : result.getErrors()) {
							System.debug('❌ ERROR updating OrderItem ' + result.getId() + ': ' + err.getMessage());
							System.debug('  Fields: ' + err.getFields());
							System.debug('  Status Code: ' + err.getStatusCode());
						}
					}
				}
				if (hasErrors) {
					System.debug('⚠️ WARNING: Some OrderItems failed to update, but payment was successful. Errors logged above.');
					// Don't set success = false here - payment was successful, OrderItem update is secondary
				}
			}
		}

		return pageRef;
	}

	/**
	 * Create Membership and User after payment completion (called asynchronously)
	 * This method is called after payment is successful to avoid transaction/callout issues
	 */
	@future
	public static void createMembershipAndUserAfterPayment(Id orderItemId, Id accountId, Id contactId) {
		System.debug('=== createMembershipAndUserAfterPayment - START ===');
		System.debug('OrderItem ID: ' + orderItemId);
		System.debug('Account ID: ' + accountId);
		System.debug('Contact ID: ' + contactId);
		
		try {
			// Get OrderItem with Order details
			List<OrderItem> orderItems = [
				SELECT Id, OrderId, UnitPrice, Product2.ProductCode, Product2Id, Order.Lead__c, Order.AccountId
				FROM OrderItem 
				WHERE Id = :orderItemId 
				LIMIT 1
			];
			
			if (orderItems.isEmpty()) {
				System.debug('❌ ERROR: OrderItem not found with ID: ' + orderItemId);
				return;
			}
			
			OrderItem oi = orderItems[0];
			
			// Query Order separately to ensure we get Lead__c (relationship query might not work in @future)
			List<Order> orderList = [SELECT Id, AccountId, Lead__c FROM Order WHERE Id = :oi.OrderId LIMIT 1];
			Order order = orderList.isEmpty() ? null : orderList[0];
			
			if (order == null) {
				System.debug('❌ ERROR: Order not found with ID: ' + oi.OrderId);
				return;
			}
			
			System.debug('Order Details:');
			System.debug('  Order.Id: ' + order.Id);
			System.debug('  Order.AccountId: ' + order.AccountId);
			System.debug('  Order.Lead__c: ' + order.Lead__c);
			
			// Use provided accountId and contactId (preserved from registration)
			Id accountIdToUse = accountId != null ? accountId : order.AccountId;
			Id contactIdToUse = contactId;
			
			System.debug('Using AccountId: ' + accountIdToUse);
			System.debug('Using ContactId: ' + contactIdToUse);
			
			// Update Account status to "Provisional" after successful payment
			if (accountIdToUse != null) {
				try {
					Account accToUpdate = new Account(
						Id = accountIdToUse,
						Current_Active_Action_Status__c = 'Provisional',
						Current_Active_Action_Start_Date__c = System.today()
					);
					
					Database.SaveResult updateResult = Database.update(accToUpdate, false);
					
					if (updateResult.isSuccess()) {
						System.debug('✅ Account status updated to Provisional: ' + accountIdToUse);
					} else {
						System.debug('❌ Account status update failed:');
						for (Database.Error err : updateResult.getErrors()) {
							System.debug('  Error: ' + err.getMessage());
						}
					}
				} catch (Exception accEx) {
					System.debug('❌ ERROR updating Account status: ' + accEx.getMessage());
				}
			}
			
			// Create Membership record
			if (accountIdToUse != null) {
				System.debug('📋 Creating Membership record...');
				try {
					Membership__c membership = createMembership(accountIdToUse, oi.UnitPrice, System.today(), CE_MEMBERSHIP_DURATION);
					System.debug('✅✅✅ MEMBERSHIP CREATED: ' + membership.Id);
					
					// Link Membership to OrderItem
					oi.Membership__c = membership.Id;
					Database.update(oi, false);
					System.debug('✅ OrderItem linked to Membership: ' + membership.Id);
				} catch (Exception memEx) {
					System.debug('❌ ERROR creating Membership: ' + memEx.getMessage());
					System.debug('❌ Stack trace: ' + memEx.getStackTraceString());
				}
			}
			
			// Create User if ContactId is provided (for new registrations)
			// Note: contactId is only provided for new registrations, so if it's not null, we should create User
			System.debug('📋📋📋 USER CREATION CHECK:');
			System.debug('  contactIdToUse: ' + contactIdToUse);
			System.debug('  order.Lead__c: ' + order.Lead__c);
			System.debug('  Will create User: ' + (contactIdToUse != null));
			
			if (contactIdToUse != null) {
				System.debug('📋 Creating User record using ContactId: ' + contactIdToUse);
				try {
					// Get Contact
					System.debug('📋 Querying Contact with ID: ' + contactIdToUse);
					List<Contact> contacts = [
						SELECT Id, FirstName, LastName, Email, Phone, Title, AccountId
						FROM Contact 
						WHERE Id = :contactIdToUse 
						LIMIT 1
					];
					
					System.debug('📋 Contact query result: ' + (contacts.isEmpty() ? 'NOT FOUND' : 'FOUND'));
					
					if (!contacts.isEmpty()) {
						Contact con = contacts[0];
						System.debug('✅ Contact found:');
						System.debug('  Contact.Id: ' + con.Id);
						System.debug('  Contact.FirstName: ' + con.FirstName);
						System.debug('  Contact.LastName: ' + con.LastName);
						System.debug('  Contact.Email: ' + con.Email);
						
						// Check if User already exists
						System.debug('📋 Checking if User already exists for Contact: ' + con.Id);
						List<User> existingUsers = [
							SELECT Id, Username, Email, IsActive
							FROM User 
							WHERE ContactId = :con.Id 
							LIMIT 1
						];
						
						System.debug('📋 Existing Users query result: ' + (existingUsers.isEmpty() ? 'NO USER EXISTS' : 'USER EXISTS: ' + existingUsers[0].Id));
						
						if (existingUsers.isEmpty()) {
							// Get Profile
							System.debug('📋 Querying Profile "CE Provider Administrator" with UserType "PowerCustomerSuccess"');
							List<Profile> profileList = [
								SELECT Id, Name, UserType 
								FROM Profile 
								WHERE Name = 'CE Provider Administrator' 
								AND UserType = 'PowerCustomerSuccess' 
								LIMIT 1
							];
							
							System.debug('📋 Profile query result: ' + (profileList.isEmpty() ? 'NOT FOUND' : 'FOUND: ' + profileList[0].Id));
							
							if (!profileList.isEmpty()) {
								Id profileId = profileList[0].Id;
								
								// Generate alias
								String alias = (con.FirstName != null && con.FirstName.length() >= 2) 
									? con.FirstName.substring(0, 2) 
									: (con.LastName != null && con.LastName.length() >= 2) 
										? con.LastName.substring(0, 2) 
										: 'usr';
								alias += String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 3);
								
								// Generate username
								String username = con.Email;
								if (username != null && !username.endsWith('@ceprovider.fsmtb.org')) {
									if (username.contains('@')) {
										username = username.substring(0, username.indexOf('@'));
									}
									username = username + '@ceprovider.fsmtb.org';
								}
								
								// Create User
								System.debug('📋 Creating User with:');
								System.debug('  Username: ' + username);
								System.debug('  Email: ' + con.Email);
								System.debug('  FirstName: ' + con.FirstName);
								System.debug('  LastName: ' + con.LastName);
								System.debug('  ContactId: ' + con.Id);
								System.debug('  ProfileId: ' + profileId);
								
								User newUser = new User(
									FirstName = con.FirstName,
									LastName = con.LastName,
									Username = username,
									Email = con.Email,
									Phone = con.Phone,
									Title = con.Title,
									Alias = alias,
									ContactId = con.Id,
									ProfileId = profileId,
									TimeZoneSidKey = 'America/New_York',
									LocaleSidKey = 'en_US',
									EmailEncodingKey = 'UTF-8',
									LanguageLocaleKey = 'en_US',
									IsActive = true
								);
								
								System.debug('📋 Attempting to insert User...');
								Database.SaveResult userResult = Database.insert(newUser, false);
								
								if (userResult.isSuccess()) {
									createdUserId = newUser.Id;
									userCreatedId = newUser.Id;
									
									System.debug('✅✅✅ USER CREATED SUCCESSFULLY ✅✅✅');
									System.debug('✅✅✅ USER ID: ' + newUser.Id + ' ✅✅✅');
									System.debug('✅ Username: ' + newUser.Username);
									System.debug('✅ Email: ' + newUser.Email);
									System.debug('✅ First Name: ' + newUser.FirstName);
									System.debug('✅ Last Name: ' + newUser.LastName);
								} else {
									System.debug('❌❌❌ USER CREATION FAILED ❌❌❌');
									for (Database.Error err : userResult.getErrors()) {
										System.debug('❌ Error: ' + err.getMessage());
										System.debug('❌ Fields: ' + err.getFields());
										System.debug('❌ Status Code: ' + err.getStatusCode());
									}
									throw new DmlException('User creation failed: ' + userResult.getErrors()[0].getMessage());
								}
								
								// Send Welcome email
								try {
									Site.forgotPassword(newUser.Username);
									System.debug('✅ Welcome email sent to: ' + newUser.Email);
								} catch (Exception emailEx) {
									System.debug('⚠️ Warning: Could not send welcome email: ' + emailEx.getMessage());
								}
							} else {
								System.debug('❌ ERROR: Profile "CE Provider Administrator" not found');
							}
						} else {
							System.debug('✅ User already exists: ' + existingUsers[0].Id);
						}
					} else {
						System.debug('❌ ERROR: Contact not found with ID: ' + contactIdToUse);
					}
				} catch (Exception userEx) {
					System.debug('❌ ERROR creating User: ' + userEx.getMessage());
					System.debug('❌ Stack trace: ' + userEx.getStackTraceString());
				}
			} else {
				System.debug('⚠️ Skipping User creation:');
				System.debug('  contactId: ' + contactIdToUse);
				System.debug('  order.Lead__c: ' + order.Lead__c);
			}
			
		} catch (Exception e) {
			System.debug('❌ ERROR in createMembershipAndUserAfterPayment: ' + e.getMessage());
			System.debug('❌ Stack trace: ' + e.getStackTraceString());
		}
		
		System.debug('=== createMembershipAndUserAfterPayment - END ===');
	}

	private static void processCerMembership(OrderItem oi, Id preservedAccountId, Id preservedContactId) {
        System.debug('=== processCerMembership - START ===');
        System.debug('OrderItem.Id: ' + oi.Id);
        System.debug('OrderItem.OrderId: ' + oi.OrderId);
        System.debug('Preserved AccountId (from registration): ' + preservedAccountId);
        System.debug('Preserved ContactId (from registration): ' + preservedContactId);
        
        // Use preserved AccountId and ContactId from registration (user requested: don't query, preserve from registration)
        Id accountId = preservedAccountId;
        Id contactId = preservedContactId;
        
        // Still need to query Order to check if it's a new registration (has Lead__c)
        List<Order> orderList = [SELECT Id, AccountId, Lead__c FROM Order WHERE Id = :oi.OrderId LIMIT 1];
        if (orderList.isEmpty()) {
            System.debug('❌ ERROR: Order not found with ID: ' + oi.OrderId);
            throw new QueryException('Order not found with ID: ' + oi.OrderId);
        }
        Order order = orderList[0];
        
        System.debug('Order Details:');
        System.debug('  Order.Id: ' + order.Id);
        System.debug('  Order.AccountId: ' + order.AccountId);
        System.debug('  Order.Lead__c: ' + order.Lead__c);
        
        // IMPORTANT: Use preserved AccountId from registration (don't query)
        if (accountId == null) {
            // Fallback: Use Order.AccountId if preserved AccountId is null (shouldn't happen)
            accountId = order.AccountId;
            System.debug('⚠️ WARNING: Preserved AccountId is null, using Order.AccountId: ' + accountId);
        } else {
            System.debug('✅ Using preserved AccountId from registration: ' + accountId);
        }
        
        // Update Account status if we found the Account
        if (accountId != null) {
            try {
                // First, verify the Account exists and get current status
                List<Account> accountsToVerify = [
                    SELECT Id, Name, Current_Active_Action_Status__c, RecordType.DeveloperName
                    FROM Account 
                    WHERE Id = :accountId 
                    LIMIT 1
                ];
                
                if (accountsToVerify.isEmpty()) {
                    System.debug('❌ ERROR: Account ' + accountId + ' not found in database!');
                } else {
                    Account currentAccount = accountsToVerify[0];
                    System.debug('📋 BEFORE UPDATE:');
                    System.debug('  Account.Id: ' + currentAccount.Id);
                    System.debug('  Account.Name: ' + currentAccount.Name);
                    System.debug('  RecordType: ' + currentAccount.RecordType.DeveloperName);
                    System.debug('  Current_Active_Action_Status__c: ' + currentAccount.Current_Active_Action_Status__c);
                    
                    // Update Account status to "Provisional" after successful payment
                    Account accToUpdate = new Account(
                        Id = accountId,
                        Current_Active_Action_Status__c = 'Provisional',
                        Current_Active_Action_Start_Date__c = System.today()
                    );
                    
                    // Use Database.update with allOrNone=false to see partial failures
                    Database.SaveResult updateResult = Database.update(accToUpdate, false);
                    
                    if (updateResult.isSuccess()) {
                        System.debug('✅ UPDATE SUCCESSFUL: Database.update() completed successfully');
                        System.debug('  Updated Account Id: ' + updateResult.getId());
                    } else {
                        System.debug('❌ UPDATE FAILED:');
                        for (Database.Error err : updateResult.getErrors()) {
                            System.debug('  Error: ' + err.getMessage());
                            System.debug('  Fields: ' + err.getFields());
                            System.debug('  Status Code: ' + err.getStatusCode());
                        }
                        // Don't throw - log the error but continue
                    }
                    
                    // Verify the update worked
                    List<Account> updatedAccounts = [
                        SELECT Id, Name, Current_Active_Action_Status__c, Current_Active_Action_Start_Date__c 
                        FROM Account 
                        WHERE Id = :accountId 
                        LIMIT 1
                    ];
                    
                    if (!updatedAccounts.isEmpty()) {
                        Account verifiedAccount = updatedAccounts[0];
                        System.debug('📋 AFTER UPDATE (VERIFIED):');
                        System.debug('  Account.Id: ' + verifiedAccount.Id);
                        System.debug('  Account.Name: ' + verifiedAccount.Name);
                        System.debug('  Current_Active_Action_Status__c: ' + verifiedAccount.Current_Active_Action_Status__c);
                        System.debug('  Current_Active_Action_Start_Date__c: ' + verifiedAccount.Current_Active_Action_Start_Date__c);
                        
                        if (verifiedAccount.Current_Active_Action_Status__c == 'Provisional') {
                            System.debug('✅✅✅ SUCCESS: Account status is now Provisional!');
                        } else {
                            System.debug('❌❌❌ ERROR: Account status was NOT updated! Still: ' + verifiedAccount.Current_Active_Action_Status__c);
                        }
                    }
                }
                
                // Create Membership record for new registration
                System.debug('📋📋📋 Creating Membership record...');
                System.debug('  Account ID: ' + accountId);
                System.debug('  Unit Price: ' + oi.UnitPrice);
                System.debug('  Start Date: ' + System.today());
                System.debug('  Duration: ' + CE_MEMBERSHIP_DURATION + ' months');
                try {
                    Membership__c membership = createMembership(accountId, oi.UnitPrice, System.today(), CE_MEMBERSHIP_DURATION);
                    System.debug('✅✅✅ MEMBERSHIP CREATED SUCCESSFULLY ✅✅✅');
                    System.debug('✅✅✅ MEMBERSHIP ID: ' + membership.Id + ' ✅✅✅');
                    System.debug('✅ Account: ' + membership.Account__c);
                    System.debug('✅ Start Date: ' + membership.Start_Date__c);
                    System.debug('✅ Expiration Date: ' + membership.Expiration_Date__c);
                    System.debug('✅ Cost: ' + membership.Cost__c);
                    
                    // Link Membership to OrderItem
                    oi.Membership__c = membership.Id;
                    System.debug('✅✅✅ OrderItem linked to Membership: ' + membership.Id);
                } catch (Exception memEx) {
                    System.debug('❌❌❌ ERROR creating Membership: ' + memEx.getMessage());
                    System.debug('❌ Error type: ' + memEx.getTypeName());
                    System.debug('❌ Stack trace: ' + memEx.getStackTraceString());
                    // Don't throw - Account was created and status updated, Membership can be created later
                }
                
                // Create User and send Welcome email (if not already exists)
                // Use preserved ContactId from registration (user requested: don't query, preserve from registration)
                System.debug('📋📋📋 USER CREATION CHECK:');
                System.debug('  contactId: ' + contactId);
                System.debug('  order.Lead__c: ' + order.Lead__c);
                System.debug('  Will create User: ' + (contactId != null && order.Lead__c != null));
                
                if (contactId != null && order.Lead__c != null) {
                    System.debug('📋 Creating User record using preserved ContactId: ' + contactId);
                    try {
                        // Get Contact using preserved ContactId (user requested: use preserved ContactId)
                        List<Contact> contacts = [
                            SELECT Id, FirstName, LastName, Email, Phone, Title
                            FROM Contact 
                            WHERE Id = :contactId 
                            LIMIT 1
                        ];
                        
                        if (!contacts.isEmpty()) {
                            Contact con = contacts[0];
                            
                            // Check if User already exists for this Contact
                            List<User> existingUsers = [
                                SELECT Id, Username, Email, IsActive
                                FROM User 
                                WHERE ContactId = :con.Id 
                                LIMIT 1
                            ];
                            
                            if (existingUsers.isEmpty()) {
                                // User doesn't exist - create it
                                System.debug('📋 User does not exist - creating new User...');
                                
                                // Get Profile "CE Provider Administrator" with UserType "PowerCustomerSuccess" (Customer Community Plus license)
                                List<Profile> profileList = [
                                    SELECT Id, Name, UserType 
                                    FROM Profile 
                                    WHERE Name = 'CE Provider Administrator' 
                                    AND UserType = 'PowerCustomerSuccess' 
                                    LIMIT 1
                                ];
                                
                                if (!profileList.isEmpty()) {
                                    Id profileId = profileList[0].Id;
                                    
                                    // Generate alias
                                    String alias = (con.FirstName != null && con.FirstName.length() >= 2) 
                                        ? con.FirstName.substring(0, 2) 
                                        : (con.LastName != null && con.LastName.length() >= 2) 
                                            ? con.LastName.substring(0, 2) 
                                            : 'usr';
                                    alias += String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 3);
                                    
                                    // Generate username: email_CE (user requested format)
                                    String username = con.Email;
                                    if (username != null && !username.endsWith('@ceprovider.fsmtb.org')) {
                                        // Remove @domain if present and add @ceprovider.fsmtb.org
                                        if (username.contains('@')) {
                                            username = username.substring(0, username.indexOf('@'));
                                        }
                                        username = username + '@ceprovider.fsmtb.org';
                                    }
                                    
                                    // Create User with CE Provider Administrator profile and Customer Community Plus license
                                    User newUser = new User(
                                        FirstName = con.FirstName,
                                        LastName = con.LastName,
                                        Username = username,
                                        Email = con.Email,
                                        Phone = con.Phone,
                                        Title = con.Title,
                                        Alias = alias,
                                        ContactId = con.Id,
                                        ProfileId = profileId,
                                        TimeZoneSidKey = 'America/New_York',
                                        LocaleSidKey = 'en_US',
                                        EmailEncodingKey = 'UTF-8',
                                        LanguageLocaleKey = 'en_US',
                                        IsActive = true
                                    );
                                    
                                    insert newUser;
                                    createdUserId = newUser.Id; // Store for console logging
                                    userCreatedId = newUser.Id; // Also set userCreatedId for response
                                    System.debug('✅✅✅ USER CREATED SUCCESSFULLY ✅✅✅');
                                    System.debug('✅✅✅ USER ID: ' + newUser.Id + ' ✅✅✅');
                                    System.debug('✅ Username: ' + newUser.Username);
                                    System.debug('✅ Email: ' + newUser.Email);
                                    System.debug('✅ First Name: ' + newUser.FirstName);
                                    System.debug('✅ Last Name: ' + newUser.LastName);
                                    System.debug('✅ Profile: CE Provider Administrator');
                                    System.debug('✅ License: Customer Community Plus (PowerCustomerSuccess)');
                                    System.debug('✅ Contact ID: ' + newUser.ContactId);
                                    
                                    // Send Welcome email (password reset email)
                                    try {
                                        Site.forgotPassword(newUser.Username);
                                        System.debug('✅ Welcome email sent to: ' + newUser.Email);
                                    } catch (Exception emailEx) {
                                        System.debug('⚠️ Warning: Could not send welcome email: ' + emailEx.getMessage());
                                        // Don't throw - User was created successfully
                                    }
                                    
                                    // Set owner for email sending
                                    owner = newUser;
                                } else {
                                    System.debug('❌ ERROR: Profile "CE Provider Administrator" with UserType "PowerCustomerSuccess" not found');
                                }
                            } else {
                                // User already exists
                                System.debug('✅ User already exists: ' + existingUsers[0].Id);
                                owner = existingUsers[0];
                            }
                        } else {
                            System.debug('⚠️ WARNING: Contact not found with preserved ContactId: ' + contactId);
                        }
                    } catch (Exception userEx) {
                        System.debug('❌ ERROR creating User: ' + userEx.getMessage());
                        System.debug('❌ Error type: ' + userEx.getTypeName());
                        System.debug('❌ Stack trace: ' + userEx.getStackTraceString());
                        // Don't throw - payment was successful, User creation can be done later
                    }
                } else {
                    System.debug('❌❌❌ USER CREATION SKIPPED:');
                    if (contactId == null) {
                        System.debug('❌❌❌ ERROR: ContactId is null - cannot create User');
                        System.debug('❌ This means ContactId was not preserved from registration or not passed to processOrders');
                    }
                    if (order.Lead__c == null) {
                        System.debug('⚠️ WARNING: Order.Lead__c is null - this may be a renewal, skipping User creation');
                    }
                    if (contactId == null && order.Lead__c != null) {
                        System.debug('❌❌❌ CRITICAL: ContactId is null but Order.Lead__c is not null - User should be created but ContactId is missing!');
                    }
                }
                
            } catch (Exception e) {
                System.debug('❌ ERROR updating Account status: ' + e.getMessage());
                System.debug('❌ Error type: ' + e.getTypeName());
                System.debug('❌ Stack trace: ' + e.getStackTraceString());
                // Don't throw - payment was successful, status update is secondary
            }
        } else {
            System.debug('⚠️ Warning: Could not find Account to update status. AccountId is null.');
        }
        
        // Payment processing complete for LWC flow
        System.debug('=== processCerMembership - END (LWC flow) ===');
        return;
        
        /* COMMENTED OUT FOR GUEST USER PERMISSIONS
        if (order.Lead__c == null) {
            throw new QueryException('Order.Lead__c is null. This is required for new registrations.');
        }
        
        List<Lead> leadList = [SELECT Id, Company, Website, Email, Street, City, StateCode, PostalCode, Phone, Fax, CountryCode, FirstName, LastName,
                            Portal_Admin_Username__c, Portal_Admin_Email__c, Portal_Admin_Phone__c, Portal_Admin_Title__c, LeadSource
                        FROM Lead WHERE Id = :order.Lead__c LIMIT 1];
        if (leadList.isEmpty()) {
            throw new QueryException('Lead not found with ID: ' + order.Lead__c);
        }
        Lead lead = leadList[0];
        
        Account a;
        Id existingAccountId = order.AccountId;
        
        if (existingAccountId != null) {
            List<Account> existingAccounts = [
                SELECT Id, Name, Portal_Account_Owner__c, Current_Active_Action_Status__c,
                       Current_Active_Action_Start_Date__c, Registration_Status__c
                FROM Account 
                WHERE Id = :existingAccountId 
                LIMIT 1
            ];
            if (!existingAccounts.isEmpty()) {
                Account existingAcc = existingAccounts[0];
                if (existingAcc.Name != 'New Membership Account') {
                    a = existingAcc;
                }
            }
        }
        
        if (a == null) {
            List<RecordType> rtList = [SELECT Id FROM RecordType WHERE DeveloperName = 'CE_Provider' AND SObjectType = 'Account' LIMIT 1];
            if (rtList.isEmpty()) {
                throw new QueryException('RecordType CE_Provider not found for Account');
            }
            a = createCommunityAccount(lead, rtList[0].Id);
        }

        Contact con;
        List<Contact> existingContacts = [
            SELECT Id, FirstName, LastName, Email, AccountId 
            FROM Contact 
            WHERE AccountId = :a.Id 
            AND Email = :lead.Portal_Admin_Email__c
            AND FirstName = :lead.FirstName
            AND LastName = :lead.LastName
            LIMIT 1
        ];
        
        if (!existingContacts.isEmpty()) {
            con = existingContacts[0];
        } else {
            List<RecordType> conRTList = [
                SELECT Id, DeveloperName 
                FROM RecordType 
                WHERE SObjectType = 'Contact' 
                AND DeveloperName = 'CE_Provider_User' 
                LIMIT 1
            ];
            if (conRTList.isEmpty()) {
                throw new QueryException('Contact RecordType CE_Provider_User not found.');
            }
            
            con = new Contact(
                AccountId = a.Id,
                RecordTypeId = conRTList[0].Id,
                FirstName = lead.FirstName,
                LastName = lead.LastName,
                Email = lead.Portal_Admin_Email__c,
                Phone = lead.Portal_Admin_Phone__c,
                Title = lead.Portal_Admin_Title__c,
                Portal_Username__c = lead.Portal_Admin_Username__c != null 
                    ? lead.Portal_Admin_Username__c.replace('@ceprovider.fsmtb.org', '') 
                    : null
            );
            insert con;
        }
        
        List<Profile> profileList = [
            SELECT Id, Name, UserType 
            FROM Profile 
            WHERE Name = 'CE Provider Administrator' 
            AND UserType = 'PowerCustomerSuccess' 
            LIMIT 1
        ];
        if (profileList.isEmpty()) {
            throw new QueryException('Profile "CE Provider Administrator" not found.');
        }
        Id profileId = profileList[0].Id;
        
        String alias = (lead.FirstName != null && lead.FirstName.length() >= 2) 
            ? lead.FirstName.substring(0, 2) 
            : (lead.LastName != null && lead.LastName.length() >= 2) 
                ? lead.LastName.substring(0, 2) 
                : 'usr';
        alias += String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 3);
        
        owner = new User(
            FirstName = lead.FirstName,
            LastName = lead.LastName,
            Username = lead.Portal_Admin_Username__c,
            Email = lead.Portal_Admin_Email__c,
            Phone = lead.Portal_Admin_Phone__c,
            Title = lead.Portal_Admin_Title__c,
            Alias = alias,
            ContactId = con.Id,
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = true
        );
        insert owner;

        Site.forgotPassword(owner.Username);

        // Set Account Status to "Provisional" after successful payment
        // This updates Current_Active_Action_Status__c which drives the Status formula field
        try {
            a.Current_Active_Action_Status__c = 'Provisional';
            a.Current_Active_Action_Start_Date__c = System.today();
            update a;
            System.debug('✅ Account status set to Provisional for Account: ' + a.Id);
        } catch (Exception e) {
            System.debug('⚠️ Warning: Could not update Account status: ' + e.getMessage());
            // Continue processing - this is not critical for payment completion
        }

        // Skip CE_Action__c, Membership, Terms Acceptance, and Order update
        // to avoid permission issues in guest context.
        // All of these will be handled by triggers or scheduled processes after payment.
        
        // Membership__c membership = createMembership(a.Id,oi.UnitPrice, System.today(), CE_MEMBERSHIP_DURATION);
		// oi.Membership__c = membership.Id;

		// Order update - NOT NEEDED: Order already has the correct AccountId from registration
		// We do NOT change the Order's Account - it keeps the same Account that was created during registration
		// update new Order(Id = order.Id, AccountId = a.Id, Status = 'Activated'); // COMMENTED OUT - DO NOT UPDATE ORDER
		
		// Keep the Lead - DO NOT delete it yet
		// The Lead-to-Account conversion and Order linking will be handled by:
		// 1. A scheduled job that processes paid Orders
		// 2. Or automation triggered when the user first logs in
		// The Lead.ConvertedAccountId field can be used to track the Account
		
		// Database.delete(lead); // Commented out - keep Lead for post-payment processing
        END OF COMMENTED CODE */
    }

    private static void processCerRenewal(OrderItem oi, Id accountId) {
		// Query for existing memberships - handle both new registrations and renewals
		List<Membership__c> membershipList = [SELECT Id, Expiration_Date__c FROM Membership__c WHERE Account__c = :accountId
										ORDER BY Expiration_Date__c DESC LIMIT 1];
		
		Date startDate;
		if (membershipList.isEmpty()) {
			// No existing Membership found - this is a new registration
			// Start from today
			startDate = System.today();
			System.debug('No existing membership found for Account ' + accountId + '. Creating new membership starting from today: ' + startDate);
		} else {
			Membership__c lastMembership = membershipList[0];
			// If last membership hasn't expired yet, start the new one the day after expiration
			// Otherwise, start from today
			if (lastMembership.Expiration_Date__c != null && lastMembership.Expiration_Date__c > System.today()) {
				startDate = lastMembership.Expiration_Date__c.addDays(1);
				System.debug('Existing membership found. New membership will start the day after expiration: ' + startDate);
			} else {
				startDate = System.today();
				System.debug('Existing membership expired. Creating new membership starting from today: ' + startDate);
			}
		}
		
		// Create the membership
		Membership__c membership = createMembership(accountId, oi.UnitPrice, startDate, CE_MEMBERSHIP_DURATION);
		System.debug('Created Membership: ' + membership.Id + ' for Account: ' + accountId + ' with Start Date: ' + membership.Start_Date__c + ', Expiration Date: ' + membership.Expiration_Date__c);
		
		oi.Membership__c = membership.Id;
		// Skip Terms Acceptance creation to avoid permission issues in guest context
		// createTermsAcceptance(accountId, 'CE Registry', null);
    }

	private static Course__c processCourse(OrderItem oi) {
        List<Course__c> courseList = [SELECT Id, Category__c, Status_Selected__c, Account__c FROM Course__c WHERE Id = :oi.Course__c LIMIT 1];
        if (courseList.isEmpty()) {
            throw new QueryException('Course not found with ID: ' + oi.Course__c);
        }
        Course__c course = courseList[0];

        course.Status_Selected__c = 'Published';

        if (!course.Category__c.equalsIgnoreCase('Other')) {
            Database.update(course);
        } else {
            course.Current_Active_Action_Status__c = 'Pending';
            Database.update(course);

            Database.insert(new CE_Action__c(
                Action__c = 'Pending',
                Course__c = course.Id,
                Start_Date__c = System.today(),
                Reason__c = 'Course submitted by provider with a coursework category of "Other."'
            ));
        }

		return course;
    }

	private static void processMlvcMembership(OrderItem oi, Id accountId) {
		String siteName = 'Massage License Verification Center';
		List<Lead> leadList = [SELECT Id, Company, Website, Email, Street, City, StateCode, PostalCode, Phone, Fax, CountryCode, FirstName, LastName,
                            Portal_Admin_Username__c, Portal_Admin_Email__c, Portal_Admin_Phone__c, Portal_Admin_Title__c, LeadSource
                        FROM Lead WHERE Id = :oi.Order.Lead__c LIMIT 1];
		if (leadList.isEmpty()) {
			throw new QueryException('Lead not found with ID: ' + oi.Order.Lead__c);
		}
		Lead ld = leadList[0];

		if (ld != null) {
			List<RecordType> rtList = [SELECT Id FROM RecordType WHERE DeveloperName = 'MT_Verify' AND SObjectType = 'Account' LIMIT 1];
			if (rtList.isEmpty()) {
				throw new QueryException('RecordType MT_Verify not found for Account');
			}
			Account a = createCommunityAccount(ld, rtList[0].Id);

			User owner = CommunityUtil.createCommunityUser(createUserRecord(ld), a.Id);

			Integer duration = Integer.valueOf(oi.Product2.ProductCode.split('-')[2]);
			Membership__c membership = createMembership(a.Id,oi.UnitPrice, System.today(), duration);

			oi.Membership__c = membership.Id;

			// Skip Terms Acceptance creation to avoid permission issues in guest context
			// createTermsAcceptance(a.Id, siteName, owner.Id);

			update new Order(
				Id = oi.OrderId,
				accountId = a.Id
			);

			Database.delete(ld);
		} else {
			System.debug('renewal');
		}
		//TODO this is changing from the current payment model and there will be no registration/renwal fees.
		//else { //TODO renewal stuff
			//System.debug('renewal membership');

			//User u = [Select AccountId From User Where Id = :UserInfo.getUserId()];

            //Date expirationDate = [Select Membership_Expiration_Date__c From Account Where Id = :u.AccountId Limit 1].Membership_Expiration_Date__c;

			//Integer duration = Integer.valueOf(oi.Product2.ProductCode.split('-')[2]);
            //Membership__c membership = createMembership(u.AccountId, expirationDate, duration);

			//oi.Membership__c = membership.Id;

			//createTermsAcceptance(u.AccountId, siteName, u.Id);

			////sendEmailConfirmation(user.Id, membership.Id);
		//}
	}

	private static Membership__c createMembership(Id accountId,Decimal price, Date startDate, Integer duration) {
		Membership__c membership = new Membership__c(
            Account__c = accountId,
            Start_Date__c = startDate,
            Expiration_Date__c = startDate.addMonths(duration),
            Cost__c = price
        );
        
        System.debug('Creating Membership with: Account=' + accountId + ', Start_Date=' + startDate + ', Expiration_Date=' + startDate.addMonths(duration) + ', Cost=' + price);
        
        Database.SaveResult result = Database.insert(membership, false);
        if (!result.isSuccess()) {
            System.debug('Error creating Membership: ' + result.getErrors());
            throw new DmlException('Failed to create Membership: ' + result.getErrors()[0].getMessage());
        }
        
        System.debug('Successfully created Membership: ' + membership.Id);

		return membership;
	}

	private static Id getTermsAndConditionsId(String siteName) {
		List<Terms_and_Conditions__c> termsList = [SELECT Id FROM Terms_and_Conditions__c WHERE Site__c = :siteName ORDER BY LastModifiedDate DESC LIMIT 1];
		if (termsList.isEmpty()) {
			throw new QueryException('Terms and Conditions not found for Site: ' + siteName);
		}
		return termsList[0].Id;
	}

	private static void createTermsAcceptance(Id accountId, String siteName, Id ownerId) {
		Terms_and_Conditions_Acceptance__c termsAccept = new Terms_and_Conditions_Acceptance__c(
            Account__c = accountId,
            Terms_and_Conditions__c = getTermsAndConditionsId(siteName),
			Terms_Accepted_By__c = ownerId != null ? ownerId : UserInfo.getUserId()
        );

        insert termsAccept;
    }

	private static Account createCommunityAccount(Lead lead, Id recordTypeId) {
//        Id ownerId = [Select Id From User Where UserRole.Name = 'DEG Administrator' And Profile.Name = 'System Administrator - FSMTB' Limit 1][0].Id;
		List<User> userList = [SELECT Id FROM User WHERE FirstName = 'Laura' AND LastName = 'Simmons' AND IsActive = true LIMIT 1];
		if (userList.isEmpty()) {
			throw new QueryException('User Laura Simmons not found');
		}
		Id ownerId = userList[0].Id;

        Account account = new Account(
            Name = lead.Company,
            Website = lead.Website,
            Email__c = lead.Email,
            BillingStreet = lead.Street,
            BillingCity = lead.City,
            BillingStateCode = lead.StateCode,
            BillingPostalCode = lead.PostalCode,
            BillingCountryCode = lead.CountryCode,
            Phone = lead.Phone,
            Fax = lead.Fax,
            RecordTypeId = recordTypeId,
            OwnerId = ownerId
        );
        Database.insert(account);

        return account;
    }

	private static User createUserRecord(Lead l) {
		Id adminProfileId;

		if (l.LeadSource == 'CE Registration') {
			List<Profile> profileList = [SELECT Id FROM Profile WHERE Name = 'CE Provider Administrator' AND UserType = 'PowerCustomerSuccess' LIMIT 1];
			if (!profileList.isEmpty()) {
				adminProfileId = profileList[0].Id;
			}
		} else if (l.LeadSource == 'MT Registration') {
			List<Profile> profileList = [SELECT Id FROM Profile WHERE Name = 'MT Verify Administrator' AND UserType = 'PowerCustomerSuccess' LIMIT 1];
			if (!profileList.isEmpty()) {
				adminProfileId = profileList[0].Id;
			}
		}

		return new User (
			FirstName = l.FirstName,
			LastName = l.LastName,
			Username = l.Portal_Admin_Username__c,
			Email = l.Portal_Admin_Email__c,
			Phone = l.Portal_Admin_Phone__c,
			Title = l.Portal_Admin_Title__c,
			ProfileId = adminProfileId
		);
	}

	private static Id getValidUserIdForEmail(Id accountId) {
		// Try to get the Account owner
		try {
			List<Account> accountList = [SELECT OwnerId FROM Account WHERE Id = :accountId LIMIT 1];
			if (!accountList.isEmpty() && accountList[0].OwnerId != null) {
				return accountList[0].OwnerId;
			}
		} catch (Exception e) {
			System.debug('Could not get Account owner: ' + e.getMessage());
		}
		
		// Try to get a Contact associated with the Account
		try {
			List<Contact> contactList = [SELECT Id FROM Contact WHERE AccountId = :accountId LIMIT 1];
			if (!contactList.isEmpty()) {
				// Get the User associated with this Contact
				List<User> userList = [SELECT Id FROM User WHERE ContactId = :contactList[0].Id AND IsActive = true LIMIT 1];
				if (!userList.isEmpty()) {
					return userList[0].Id;
				}
			}
		} catch (Exception e) {
			System.debug('Could not get Contact/User: ' + e.getMessage());
		}
		
		// Fallback: try to get the current user (may not work for guest users)
		try {
			Id currentUserId = UserInfo.getUserId();
			// Verify the user exists and is active
			List<User> userList = [SELECT Id FROM User WHERE Id = :currentUserId AND IsActive = true LIMIT 1];
			if (!userList.isEmpty()) {
				return currentUserId;
			}
		} catch (Exception e) {
			System.debug('Could not get current user: ' + e.getMessage());
		}
		
		// Last resort: get a system admin user
		try {
			List<User> adminList = [SELECT Id FROM User WHERE FirstName = 'Laura' AND LastName = 'Simmons' AND IsActive = true LIMIT 1];
			if (!adminList.isEmpty()) {
				return adminList[0].Id;
			}
		} catch (Exception e) {
			System.debug('Could not get admin user: ' + e.getMessage());
		}
		
		return null;
	}

	public enum PurchaseType {
		CE_FEEDBACK,
		CE_COURSE,
		CE_MEMBERSHIP,
		CE_RENEWAL,
		MLVC_MEMBERSHIP
	}
}