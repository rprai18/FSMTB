public without sharing class CommunityOrderProcessorLWC {
    private final static Integer CE_MEMBERSHIP_DURATION = 12;

    private static Map<String, PurchaseType> pTypeMap = new Map<String, PurchaseType>{
        'cer-course' => PurchaseType.CE_COURSE,
        'cer-feedback' => PurchaseType.CE_FEEDBACK,
        'cer-membership' => PurchaseType.CE_MEMBERSHIP,
        'cer-membership-renewal' => PurchaseType.CE_RENEWAL,
        'mlvc-membership-1-month' => PurchaseType.MLVC_MEMBERSHIP,
        'mlvc-membership-3-month' => PurchaseType.MLVC_MEMBERSHIP,
        'mlvc-membership-6-month' => PurchaseType.MLVC_MEMBERSHIP,
        'mlvc-membership-12-month' => PurchaseType.MLVC_MEMBERSHIP
    };

    private static Map<PurchaseType, String> emailTemplateMap = new Map<PurchaseType, String>{
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

    public static PurchaseType getPurchaseType(Id orderId) {
        List<OrderItem> rows = [SELECT Product2.ProductCode FROM OrderItem WHERE OrderId = :orderId LIMIT 1];
        if (rows.isEmpty()) return null;
        return pTypeMap.get(rows[0].Product2.ProductCode);
    }

    public static PageReference processOrders(Id accountId, Id contactId, List<Order> orders, String transactionId) {
        if (orders == null || orders.isEmpty()) return null;

        String strbody = 'Thank you for submitting your course to the FSMTB CE Registry.<br><br>' +
            'This automated email serves as your receipt. Note: Please do not reply to this email, as this is not a monitored email account.<br><br>' +
            'Course Registration Order Details:<br><br>';

        List<Account> accountList = [SELECT Name FROM Account WHERE Id = :accountId LIMIT 1];
        if (accountList.isEmpty()) {
            throw new QueryException('Account not found with ID: ' + accountId);
        }
        String accName = accountList[0].Name;

        Set<Id> orderIds = new Set<Id>();
        for (Order o : orders) if (o != null) orderIds.add(o.Id);

        Map<Id, List<OrderItem>> itemsByOrder = new Map<Id, List<OrderItem>>();
        for (OrderItem oi : [
            SELECT Id, OrderId, UnitPrice, Course__c, Course__r.Name, Course_Name__c, Product2.ProductCode,
                   Order.Lead__c, Order.AccountId
            FROM OrderItem
            WHERE OrderId IN :orderIds
            ORDER BY CreatedDate
        ]) {
            List<OrderItem> bucket = itemsByOrder.get(oi.OrderId);
            if (bucket == null) {
                bucket = new List<OrderItem>();
                itemsByOrder.put(oi.OrderId, bucket);
            }
            bucket.add(oi);
        }

        PageReference pageRef;
        List<OrderItem> toUpdate = new List<OrderItem>();

        for (Order order : orders) {
            List<OrderItem> items = itemsByOrder.get(order.Id);
            if (items == null || items.isEmpty()) continue;

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

            PurchaseType lastType;

            for (OrderItem oi : items) {
                if (oi.Product2 == null || String.isBlank(oi.Product2.ProductCode)) {
                    System.debug('WARNING: OrderItem ' + oi.Id + ' has no Product2 or ProductCode');
                    continue;
                }

                PurchaseType pType = pTypeMap.get(oi.Product2.ProductCode);
                lastType = pType;
                System.debug('Processing OrderItem ' + oi.Id + ' with ProductCode: ' + oi.Product2.ProductCode + ', PurchaseType: ' + pType);

                if (pType == PurchaseType.CE_FEEDBACK) {
                    pageRef = Page.CEDownloadFeedback;

                } else if (pType == PurchaseType.CE_RENEWAL) {
                    System.debug('Calling processCerRenewal for OrderItem ' + oi.Id + ' with AccountId: ' + accountId);
                    try {
                        processCerRenewal(oi, accountId);
                        System.debug('Successfully processed renewal for OrderItem ' + oi.Id);
                    } catch (Exception e) {
                        System.debug('ERROR in processCerRenewal: ' + e.getMessage());
                        System.debug('Stack trace: ' + e.getStackTraceString());
                        throw e; // Re-throw to fail the transaction
                    }
                    toUpdate.add(oi);
                    pageRef = Page.PaymentConfirmation;

                } else if (pType == PurchaseType.CE_MEMBERSHIP) {
                    // Membership and User creation will be handled by @future method called from payment controller
                    // after payment transaction completes (see CeCommunityPaymentLwcController.submitPayment)
                    System.debug('OrderItem ' + oi.Id + ' processed - Membership and User will be created asynchronously');
                    toUpdate.add(oi);
                    pageRef = Page.PaymentConfirmation;

                } else if (pType == PurchaseType.CE_COURSE) {
                    Course__c c = processCourse(oi);
                    toUpdate.add(oi);

                    if (c == null) {
                        pageRef = Page.PaymentConfirmation;
                    } else if (c.Category__c == 'Other') {
                        pageRef = Page.CECourseManagement;
                        pageRef.getParameters().put('pendingReview', 'yes');
                    } else {
                        strbody += 'Course Name: ' + oi.Course_Name__c;
                        strbody += '<br>Course ID: ' + oi.Course__r.Name;
                        strbody += '<br>Account: ' + accName;
                        strbody += '<br>Purchase Date: ' + Date.today().format();
                        strbody += '<br>Transaction ID: ' + transactionId;
                        strbody += '<br>Cost: ' + order.TotalAmount;

                        pageRef = Page.CESession;
                        pageRef.getParameters().put('courseId', c.Id);
                        pageRef.getParameters().put('method', 'Add');
                        pageRef.getParameters().put('previousPage', 'CEAddCourse');
                    }

                } else if (pType == PurchaseType.MLVC_MEMBERSHIP) {
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

            if (lastType == PurchaseType.CE_COURSE) {
                try {
                    CommunityUtil.sendCeCourseEmail(strbody, order.Id);
                } catch (Exception e) {
                    insert new Credit_Card_Error__c(
                        Error_Text__c = 'CE course email failed: ' + e.getMessage()
                    );
                }
            } else if (lastType != null) {
                // Get a valid User ID for email sending
                // For renewals, owner is null, so we need to find a valid User ID
                Id targetUserId = owner != null ? owner.Id : getValidUserIdForEmail(accountId);
                String emailTemplateName = emailTemplateMap.get(lastType);
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

        if (!toUpdate.isEmpty()) Database.update(toUpdate);
        return pageRef;
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
                System.debug('📋 Creating Membership record...');
                try {
                    Membership__c membership = createMembership(accountId, oi.UnitPrice, System.today(), CE_MEMBERSHIP_DURATION);
                    System.debug('✅ Membership created: ' + membership.Id);
                    System.debug('  Start Date: ' + membership.Start_Date__c);
                    System.debug('  Expiration Date: ' + membership.Expiration_Date__c);
                    
                    // Link Membership to OrderItem
                    oi.Membership__c = membership.Id;
                    System.debug('✅ OrderItem linked to Membership');
                } catch (Exception memEx) {
                    System.debug('❌ ERROR creating Membership: ' + memEx.getMessage());
                    System.debug('❌ Error type: ' + memEx.getTypeName());
                    System.debug('❌ Stack trace: ' + memEx.getStackTraceString());
                    // Don't throw - Account was created and status updated, Membership can be created later
                }
                
                // Create User and send Welcome email (if not already exists)
                // Use preserved ContactId from registration (user requested: don't query, preserve from registration)
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
                                    System.debug('✅ User created: ' + newUser.Id);
                                    System.debug('  Username: ' + newUser.Username);
                                    System.debug('  Email: ' + newUser.Email);
                                    System.debug('  Profile: CE Provider Administrator');
                                    System.debug('  License: Customer Community Plus (PowerCustomerSuccess)');
                                    
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
                    if (contactId == null) {
                        System.debug('⚠️ WARNING: ContactId is null - cannot create User');
                    }
                    if (order.Lead__c == null) {
                        System.debug('⚠️ WARNING: Order.Lead__c is null - this may be a renewal, skipping User creation');
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
        List<Lead> leads = [SELECT Id, Company, Website, Email, Street, City, StateCode, PostalCode, Phone, Fax, CountryCode, FirstName, LastName,
                                   Portal_Admin_Username__c, Portal_Admin_Email__c, Portal_Admin_Phone__c, Portal_Admin_Title__c, LeadSource
                            FROM Lead WHERE Id = :oi.Order.Lead__c LIMIT 1];
        if (leads.isEmpty()) return;

        Lead lead = leads[0];
        Id rtId = [SELECT Id FROM RecordType WHERE DeveloperName = 'CE_Provider' AND SObjectType = 'Account' LIMIT 1].Id;

        Account a = createCommunityAccount(lead, rtId);
        System.debug('=== PROCESS CER MEMBERSHIP - START ===');
        System.debug('Account created: ' + a.Id + ', Name: ' + a.Name);
        
        // Get Contact RecordType
        List<RecordType> conRTList = [
            SELECT Id, DeveloperName 
            FROM RecordType 
            WHERE SObjectType = 'Contact' 
            AND DeveloperName = 'CE_Provider_User' 
            LIMIT 1
        ];
        System.debug('Contact RecordType query result: ' + (conRTList.isEmpty() ? 'NOT FOUND' : 'Found: ' + conRTList[0].Id));
        if (conRTList.isEmpty()) {
            throw new QueryException('Contact RecordType CE_Provider_User not found.');
        }
        
        // Create Contact from Lead
        Contact con = new Contact(
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
        System.debug('About to insert Contact with: FirstName=' + lead.FirstName + ', LastName=' + lead.LastName + ', Email=' + lead.Portal_Admin_Email__c);
        try {
            insert con;
            System.debug('SUCCESS: Contact created: ' + con.Id);
        } catch (Exception conEx) {
            System.debug('ERROR creating Contact: ' + conEx.getMessage());
            System.debug('Stack trace: ' + conEx.getStackTraceString());
            throw conEx;
        }
        
        // Get Profile for CE Provider Administrator
        List<Profile> profileList = [
            SELECT Id, Name, UserType 
            FROM Profile 
            WHERE Name = 'CE Provider Administrator' 
            AND UserType = 'PowerCustomerSuccess' 
            LIMIT 1
        ];
        System.debug('Profile query result: ' + (profileList.isEmpty() ? 'NOT FOUND' : 'Found: ' + profileList[0].Id + ', Name: ' + profileList[0].Name));
        if (profileList.isEmpty()) {
            throw new QueryException('Profile "CE Provider Administrator" not found.');
        }
        Id profileId = profileList[0].Id;
        
        // Create User linked to Contact
        String username = lead.Portal_Admin_Username__c;
        System.debug('Username from Lead: ' + username);
        if (String.isBlank(username)) {
            throw new QueryException('Portal admin username is missing on the Lead.');
        }
        
        // Generate alias (required field)
        String alias = (lead.FirstName != null && lead.FirstName.length() >= 2) 
            ? lead.FirstName.substring(0, 2) 
            : (lead.LastName != null && lead.LastName.length() >= 2) 
                ? lead.LastName.substring(0, 2) 
                : 'usr';
        alias += String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 3);
        System.debug('Generated alias: ' + alias);
        
        owner = new User(
            FirstName = lead.FirstName,
            LastName = lead.LastName,
            Username = username,
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
        
        System.debug('About to insert User with:');
        System.debug('  FirstName: ' + owner.FirstName);
        System.debug('  LastName: ' + owner.LastName);
        System.debug('  Username: ' + owner.Username);
        System.debug('  Email: ' + owner.Email);
        System.debug('  ContactId: ' + owner.ContactId);
        System.debug('  ProfileId: ' + owner.ProfileId);
        System.debug('  Alias: ' + owner.Alias);
        System.debug('  IsActive: ' + owner.IsActive);
        
        try {
            insert owner;
            System.debug('SUCCESS: User created: ' + owner.Id);
            System.debug('User details - Username: ' + owner.Username + ', Email: ' + owner.Email + ', ContactId: ' + owner.ContactId);
            
            // Verify the User was created and linked
            List<User> verifyUser = [
                SELECT Id, Username, Email, ContactId, ProfileId, IsActive 
                FROM User 
                WHERE Id = :owner.Id 
                LIMIT 1
            ];
            if (!verifyUser.isEmpty()) {
                System.debug('VERIFICATION: User exists in database:');
                System.debug('  UserId: ' + verifyUser[0].Id);
                System.debug('  Username: ' + verifyUser[0].Username);
                System.debug('  ContactId: ' + verifyUser[0].ContactId);
                System.debug('  ProfileId: ' + verifyUser[0].ProfileId);
                System.debug('  IsActive: ' + verifyUser[0].IsActive);
            } else {
                System.debug('ERROR: User was not found in database after insert!');
            }
        } catch (Exception userEx) {
            System.debug('ERROR creating User: ' + userEx.getMessage());
            System.debug('Error type: ' + userEx.getTypeName());
            System.debug('Stack trace: ' + userEx.getStackTraceString());
            if (userEx instanceof DmlException) {
                DmlException dmlEx = (DmlException)userEx;
                System.debug('DML Exception details:');
                for (Integer i = 0; i < dmlEx.getNumDml(); i++) {
                    System.debug('  Error ' + i + ': ' + dmlEx.getDmlMessage(i));
                    System.debug('  Status Code: ' + dmlEx.getDmlStatusCode(i));
                    System.debug('  Fields: ' + dmlEx.getDmlFields(i));
                }
            }
            throw userEx;
        }
        System.debug('=== PROCESS CER MEMBERSHIP - USER CREATION COMPLETE ===');

        // Send password reset email to the newly created user
        // Using Site.forgotPassword() which automatically sends email for community users
        // This is the recommended approach for Experience Cloud users
        try {
            if (String.isNotBlank(owner.Username) && String.isNotBlank(owner.Email)) {
                System.debug('Attempting to send password reset email to user: ' + owner.Id);
                System.debug('Username: ' + owner.Username);
                System.debug('Email: ' + owner.Email);
                
                // For community users, Site.forgotPassword() is the correct method
                // It automatically sends the password reset email
                Site.forgotPassword(owner.Username);
                
                System.debug('Site.forgotPassword() called successfully for username: ' + owner.Username);
                emailStatusMessage = 'SUCCESS: Password reset email sent via Site.forgotPassword() to ' + owner.Email;
                emailSentTo = owner.Email;
            } else {
                System.debug('Warning: Username or Email is blank for user: ' + owner.Id + ', cannot send password reset email');
                emailStatusMessage = 'WARNING: Username or Email is blank. Username: ' + (String.isNotBlank(owner.Username) ? owner.Username : 'BLANK') + ', Email: ' + (String.isNotBlank(owner.Email) ? owner.Email : 'BLANK');
            }
        } catch (Exception e) {
            System.debug('ERROR sending custom password reset email: ' + e.getMessage());
            System.debug('Error type: ' + e.getTypeName());
            System.debug('Stack trace: ' + e.getStackTraceString());
            emailStatusMessage = 'EXCEPTION: ' + e.getTypeName() + ' - ' + e.getMessage();
            if (owner != null && String.isNotBlank(owner.Email)) {
                emailSentTo = owner.Email;
            }
            // Don't fail the transaction if email fails
        }
        
        // Store user ID for debugging
        if (owner != null && owner.Id != null) {
            userCreatedId = owner.Id;
        }
        
        // IMPORTANT: We don't query the User to verify it exists because:
        // 1. In 'without sharing' context, we may not be able to query Community Users
        // 2. If insert owner succeeded and owner.Id is populated, the User definitely exists
        // 3. The User ID from the insert result is guaranteed to be valid and committed
        // 4. Querying Community Users in 'without sharing' context can fail due to org-level User visibility settings
        
        if (owner == null || owner.Id == null) {
            String errorMsg = 'ERROR: User was not created successfully. owner is null or owner.Id is null.';
            System.debug('❌❌❌ ' + errorMsg);
            throw new DmlException(errorMsg);
        }
        
        if (a == null || a.Id == null) {
            String errorMsg = 'ERROR: Account is null or Account ID is null.';
            System.debug('❌❌❌ ' + errorMsg);
            throw new DmlException(errorMsg);
        }
        
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
        // The payment transaction completes successfully, and post-payment automation
        // will handle linking Order to Account, creating Membership, etc.
        
        // Membership__c membership = createMembership(a.Id, oi.UnitPrice, System.today(), CE_MEMBERSHIP_DURATION);
        // oi.Membership__c = membership.Id;
        
        // Order update - NOT NEEDED: Order already has the correct AccountId from registration
        // We do NOT change the Order's Account - it keeps the same Account that was created during registration
        // oi.Order.AccountId = a.Id; // COMMENTED OUT - DO NOT UPDATE ORDER
        // update new Order(Id = oi.OrderId, AccountId = a.Id, Status = 'Activated'); // COMMENTED OUT - DO NOT UPDATE ORDER

        Database.delete(lead);
        END OF COMMENTED CODE */
    }

    private static void processCerRenewal(OrderItem oi, Id accountId) {
        // Query for existing memberships - handle both new registrations and renewals
        List<Membership__c> membershipList = [SELECT Id, Expiration_Date__c FROM Membership__c WHERE Account__c = :accountId ORDER BY Expiration_Date__c DESC LIMIT 1];
        
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
        Membership__c membership = createMembership(
            accountId,
            oi.UnitPrice,
            startDate,
            CE_MEMBERSHIP_DURATION
        );
        System.debug('Created Membership: ' + membership.Id + ' for Account: ' + accountId + ' with Start Date: ' + membership.Start_Date__c + ', Expiration Date: ' + membership.Expiration_Date__c);
        
        oi.Membership__c = membership.Id;
        // Skip Terms Acceptance creation to avoid permission issues in guest context
        // createTermsAcceptance(accountId, 'CE Registry', null);
    }

    private static Course__c processCourse(OrderItem oi) {
        if (oi == null || oi.Course__c == null) return null;

        List<Course__c> rows = [
            SELECT Id, Category__c, Status_Selected__c, Account__c, Current_Active_Action_Status__c
            FROM Course__c
            WHERE Id = :oi.Course__c
            LIMIT 1
        ];
        if (rows.isEmpty()) return null;

        Course__c course = rows[0];
        course.Status_Selected__c = 'Published';
        if (course.Category__c != null && !course.Category__c.equalsIgnoreCase('Other')) {
            update course;
        } else {
            course.Current_Active_Action_Status__c = 'Pending';
            update course;
            insert new CE_Action__c(
                Action__c = 'Pending',
                Course__c = course.Id,
                Start_Date__c = System.today(),
                Reason__c = 'Course submitted by provider with a coursework category of "Other."'
            );
        }
        return course;
    }

    private static void processMlvcMembership(OrderItem oi, Id accountId) {
        String siteName = 'Massage License Verification Center';
        List<Lead> lds = [SELECT Id, Company, Website, Email, Street, City, StateCode, PostalCode, Phone, Fax, CountryCode, FirstName, LastName,
                                 Portal_Admin_Username__c, Portal_Admin_Email__c, Portal_Admin_Phone__c, Portal_Admin_Title__c, LeadSource
                          FROM Lead WHERE Id = :oi.Order.Lead__c LIMIT 1];

        if (!lds.isEmpty()) {
            Lead ld = lds[0];
            Id rtId = [SELECT Id FROM RecordType WHERE DeveloperName = 'MT_Verify' AND SObjectType = 'Account' LIMIT 1].Id;
            Account a = createCommunityAccount(ld, rtId);
            User ownerLocal = CommunityUtil.createCommunityUser(createUserRecord(ld), a.Id);
            Integer duration = Integer.valueOf(oi.Product2.ProductCode.split('-')[2]);
            Membership__c membership = createMembership(a.Id, oi.UnitPrice, System.today(), duration);
            oi.Membership__c = membership.Id;
            // Skip Terms Acceptance creation to avoid permission issues in guest context
            // createTermsAcceptance(a.Id, siteName, ownerLocal.Id);
            update new Order(Id = oi.OrderId, AccountId = a.Id);
            Database.delete(ld);
        }
    }

    private static Membership__c createMembership(Id accountId, Decimal price, Date startDate, Integer duration) {
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

    private static void createTermsAcceptance(Id accountId, String siteName, Id ownerId) {
        List<Terms_and_Conditions__c> termsList = [SELECT Id FROM Terms_and_Conditions__c WHERE Site__c = :siteName ORDER BY LastModifiedDate DESC LIMIT 1];
        if (termsList.isEmpty()) {
            throw new QueryException('Terms and Conditions not found for Site: ' + siteName);
        }
        Id termsId = termsList[0].Id;
        Terms_and_Conditions_Acceptance__c termsAccept = new Terms_and_Conditions_Acceptance__c(
            Account__c = accountId,
            Terms_and_Conditions__c = termsId,
            Terms_Accepted_By__c = ownerId != null ? ownerId : UserInfo.getUserId()
        );
        insert termsAccept;
    }

    private static Account createCommunityAccount(Lead lead, Id recordTypeId) {
        Id ownerId = [SELECT Id FROM User WHERE FirstName = 'Laura' AND LastName = 'Simmons' AND IsActive = true LIMIT 1].Id;
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
        insert account;
        return account;
    }

    private static User createUserRecord(Lead l) {
        Id adminProfileId;
        if (l.LeadSource == 'CE Registration') {
            adminProfileId = [SELECT Id FROM Profile WHERE Name = 'CE Provider Administrator' AND UserType = 'PowerCustomerSuccess' LIMIT 1].Id;
        } else if (l.LeadSource == 'MT Registration') {
            adminProfileId = [SELECT Id FROM Profile WHERE Name = 'MT Verify Administrator' AND UserType = 'PowerCustomerSuccess' LIMIT 1].Id;
        }
        return new User(
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