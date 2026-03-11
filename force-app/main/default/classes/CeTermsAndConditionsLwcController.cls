// Use without sharing for guest user operations - guest users need to create Terms, Terms Acceptance, and Orders
public without sharing class CeTermsAndConditionsLwcController {
    
    // Wrapper for terms data
    public class TermsDataWrapper {
        @AuraEnabled public String termsText { get; set; }
        @AuraEnabled public String siteName { get; set; }
        @AuraEnabled public Boolean hasTerms { get; set; }
        @AuraEnabled public String error { get; set; }
    }
    
    // Wrapper for proceed result
    public class ProceedResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public List<Id> orderIds { get; set; }
        @AuraEnabled public String redirectUrl { get; set; }
        @AuraEnabled public Boolean showAdminRedirect { get; set; }
        @AuraEnabled public Id accountId { get; set; } // Preserve AccountId for payment processing
        @AuraEnabled public Id contactId { get; set; } // Preserve ContactId for User creation after payment
    }
    
    /**
     * Get Terms and Conditions data - matches VF page getter
     * Now accepts accountId instead of leadId (since Lead is converted immediately)
     */
    @AuraEnabled(cacheable=false)
    public static TermsDataWrapper getTermsData(Id accountId) {
        TermsDataWrapper wrapper = new TermsDataWrapper();
        
        try {
            // Get site name - use getMasterLabel() like VF page
            String siteName = Site.getMasterLabel();
            wrapper.siteName = siteName;
            
            // Map site name to Site__c picklist value
            // Site.getMasterLabel() returns "CE Registry Portal" but Site__c might be "CE Provider"
            String siteValue = siteName;
            if (siteName.contains('CE Registry') || siteName == 'CE Registry Portal') {
                siteValue = 'CE Provider';
            } else if (siteName.contains('Massage License') || siteName == 'Massage License Verification Center') {
                siteValue = 'MT Verify';
            }
            
            System.debug('getTermsData - siteName: ' + siteName + ', mapped siteValue: ' + siteValue);
            
            // Get Terms_and_Conditions__c record - try both siteName and mapped value
            Terms_and_Conditions__c terms = null;
            try {
                List<Terms_and_Conditions__c> termsList = [
                    SELECT Terms_and_Conditions_Text__c, Site__c
                    FROM Terms_and_Conditions__c
                    WHERE (Site__c = :siteName OR Site__c = :siteValue)
                    AND Activation_Date__c <= TODAY
                    ORDER BY Activation_Date__c DESC, LastModifiedDate DESC
                    LIMIT 1
                ];
                
                if (!termsList.isEmpty()) {
                    terms = termsList[0];
                    System.debug('Found Terms record with Site__c: ' + terms.Site__c);
                }
            } catch (QueryException e) {
                // If query fails, create dummy record like VF page
                System.debug('QueryException in getTermsData: ' + e.getMessage());
                terms = new Terms_and_Conditions__c(
                    Site__c = siteValue,
                    Terms_and_Conditions_Text__c = 'T&C\'s have not been configured'
                );
            }
            
            // If no terms found, create dummy record like VF page
            if (terms == null) {
                System.debug('No Terms record found, creating dummy record');
                terms = new Terms_and_Conditions__c(
                    Site__c = siteValue,
                    Terms_and_Conditions_Text__c = 'T&C\'s have not been configured'
                );
            }
            
            // Format terms text for HTML display
            if (terms.Terms_and_Conditions_Text__c != null && String.isNotBlank(terms.Terms_and_Conditions_Text__c)) {
                wrapper.termsText = formatTermsForHTML(terms.Terms_and_Conditions_Text__c);
                wrapper.hasTerms = true;
            } else {
                // For new registrations, allow acceptance even if terms are not configured
                wrapper.termsText = 'T&C\'s have not been configured';
                wrapper.hasTerms = false; // Still allow acceptance for new registrations
            }
            
        } catch (Exception e) {
            // Don't block acceptance for new registrations - just log the error
            wrapper.termsText = 'T&C\'s have not been configured';
            wrapper.hasTerms = false;
            // Only set error for critical issues, not for missing terms
            if (e.getMessage().contains('FIELD_INTEGRITY_EXCEPTION') || e.getMessage().contains('INSUFFICIENT_ACCESS')) {
                wrapper.error = 'Error loading terms: ' + e.getMessage();
            }
            System.debug('Error in getTermsData: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
        }
        
        return wrapper;
    }
    
    /**
     * Proceed method - New flow: Create Terms, Acceptance, then Order
     * Accepts accountId (preferred), contactId (for User creation), and leadId (fallback for old URLs)
     */
    @AuraEnabled(cacheable=false)
    public static ProceedResult proceed(Id accountId, Id contactId, Id leadId) {
        ProceedResult result = new ProceedResult();
        result.orderIds = new List<Id>();
        result.success = false;
        result.showAdminRedirect = false;
        
        try {
            System.debug('proceed() called with accountId: ' + accountId + ', contactId: ' + contactId + ', leadId: ' + leadId);
            
            // Preserve accountId and contactId for payment processing (user requested: don't query, preserve from registration)
            result.accountId = accountId;
            result.contactId = contactId;
            
            // Get accountId - if not provided, try to get from leadId or current user
            if (accountId == null) {
                // Try to get Account from Lead (if Lead still exists and was converted)
                if (leadId != null) {
                    try {
                        List<Lead> leads = [
                            SELECT Id, ConvertedAccountId, ConvertedContactId, IsConverted
                            FROM Lead
                            WHERE Id = :leadId
                            LIMIT 1
                        ];
                        if (!leads.isEmpty() && leads[0].IsConverted && leads[0].ConvertedAccountId != null) {
                            accountId = leads[0].ConvertedAccountId;
                            System.debug('Retrieved accountId from converted Lead: ' + accountId);
                        }
                    } catch (Exception e) {
                        System.debug('Error getting Account from Lead: ' + e.getMessage());
                    }
                }
                
                // If still null, try to get from current user (for renewals)
                if (accountId == null) {
                    try {
                        User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
                        accountId = currentUser.AccountId;
                        System.debug('Retrieved accountId from current user: ' + accountId);
                    } catch (QueryException qe) {
                        System.debug('QueryException getting current user: ' + qe.getMessage());
                        // User might not exist (guest user) - this is OK for new registrations
                    } catch (Exception e) {
                        System.debug('Exception getting current user: ' + e.getMessage());
                    }
                }
            }
            
            // Validate accountId - for new registrations, this should always be present
            if (accountId == null) {
                String errorMsg = 'Account ID is required. Please ensure registration was completed successfully. If you accessed this page with an old link, please complete the registration process again.';
                System.debug('AccountId validation failed: ' + errorMsg);
                throw new AuraHandledException(errorMsg);
            }
            
            // Verify the Account exists
            try {
                List<Account> accounts = [SELECT Id, Name FROM Account WHERE Id = :accountId LIMIT 1];
                if (accounts.isEmpty()) {
                    throw new AuraHandledException('Account not found with ID: ' + accountId + '. Please ensure registration was completed successfully.');
        }
                System.debug('Verified Account exists: ' + accounts[0].Name + ' (' + accounts[0].Id + ')');
            } catch (QueryException qe) {
                System.debug('QueryException verifying Account: ' + qe.getMessage());
                throw new AuraHandledException('Error verifying Account. Please contact support.');
            }
            
            System.debug('Proceeding with accountId: ' + accountId);
            
            // Check renewal status - matches VF page checkRenewalStatus()
            if (checkRenewalStatus(accountId)) {
                result.success = false;
                result.showAdminRedirect = true;
                result.message = 'While processing this renewal, it was completed by another user. Please see the renewal information on the Account Administration page.';
                return result;
            }
            
            // Get site name
            String siteName = Site.getMasterLabel();
            
            // Step 1: Create Terms and Conditions record (if it doesn't exist)
            System.debug('Step 1: Creating Terms and Conditions record for site: ' + siteName);
            Id termsId = createTermsAndConditionsRecord(siteName);
            System.debug('Terms and Conditions record created/retrieved: ' + termsId);
            
            // Step 2: Create Terms and Conditions Acceptance record
            System.debug('Step 2: Creating Terms Acceptance for accountId: ' + accountId + ', termsId: ' + termsId);
            createTermsAcceptance(accountId, termsId, siteName);
            System.debug('Terms Acceptance created successfully');
            
            // Step 3: Create order - CRITICAL: We need leadId for new registrations
            // Even though Lead is converted to Account, we still need the Lead ID to set on Order
            // This tells payment processing that it's a new registration (not renewal)
            System.debug('Step 3: Creating Order for accountId: ' + accountId + ', leadId: ' + leadId);
            
            // If leadId is null, try to find it from the Account
            Id leadIdForOrder = leadId;
            if (leadIdForOrder == null && accountId != null) {
                System.debug('leadId is null, attempting to find Lead from Account...');
                // The Lead lookup in createOrder will handle this, but we should log it
            }
            
            List<Id> orderIds = createOrder(leadIdForOrder, accountId);
            System.debug('Order created with IDs: ' + orderIds);
            result.orderIds = orderIds;
            
            // Set redirect URL based on site - matches VF page
            if (siteName == 'CE Registry' || siteName.contains('CE Registry')) {
                result.redirectUrl = '/Payment__c'; // Community page URL for CE Registry
                result.success = true;
                result.message = 'Terms accepted successfully. Order created.';
            } else if (siteName == 'Massage License Verification Center') {
                result.redirectUrl = '/MTPaymentSelect__c'; // Community page URL for MT Verify
                result.success = true;
                result.message = 'Terms accepted successfully. Order created.';
            } else {
                result.success = false;
                result.message = 'Unknown site: ' + siteName;
    }
    
        } catch (AuraHandledException e) {
            result.success = false;
            String errorMsg = e.getMessage();
            if (String.isBlank(errorMsg)) {
                errorMsg = 'An error occurred while accepting terms. Please contact support.';
            }
            result.message = errorMsg;
            System.debug('AuraHandledException in proceed: ' + errorMsg + ' Stack: ' + e.getStackTraceString());
        } catch (DmlException dmlEx) {
            result.success = false;
            String errorMsg = 'Error creating records: ';
            if (dmlEx.getNumDml() > 0) {
                errorMsg = dmlEx.getDmlMessage(0);
            } else {
                errorMsg += dmlEx.getMessage();
            }
            result.message = errorMsg;
            System.debug('DmlException in proceed: ' + errorMsg + ' Stack: ' + dmlEx.getStackTraceString());
        } catch (Exception e) {
            result.success = false;
            String errorMsg = e.getMessage();
            if (String.isBlank(errorMsg)) {
                errorMsg = 'An unexpected error occurred while accepting terms. Please try again or contact support.';
            } else {
                errorMsg = 'Error accepting terms: ' + errorMsg;
            }
            result.message = errorMsg;
            System.debug('Unexpected exception in proceed: ' + errorMsg + ' Type: ' + e.getTypeName() + ' Stack: ' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * Check renewal status - matches CommunityRenewalFlowController.checkRenewalStatus()
     */
    private static Boolean checkRenewalStatus(Id accountId) {
        if (accountId == null) {
            return false;
        }
        
        try {
            // Check if there's a processed renewal order (not Draft)
            List<Order> processedRenewalOrders = [
                SELECT Id 
                FROM Order 
                WHERE AccountId = :accountId 
                AND Status != 'Draft'
                AND Id IN (
                    SELECT OrderId 
                    FROM OrderItem 
                    WHERE Product2.ProductCode = 'cer-membership-renewal'
                )
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            
            return !processedRenewalOrders.isEmpty();
        } catch (Exception e) {
            System.debug('Error checking renewal status: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * Create Order - matches VF page createOrder() exactly
     */
    private static List<Id> createOrder(Id leadId, Id accountId) {
        Set<Id> orderIds = new Set<Id>();
        
        try {
            // IMPORTANT: If leadId is null but accountId is provided, try to find the Lead
            // This is needed because Lead is converted to Account before Terms page, but Lead still exists
            // The Lead is needed on the Order so payment processing knows it's a new registration
            System.debug('===== LEAD LOOKUP FOR ORDER =====');
            System.debug('Initial leadId: ' + leadId);
            System.debug('accountId: ' + accountId);
            
            if (leadId == null && accountId != null) {
                try {
                    // Strategy 1: Find Lead by matching Account name (most reliable for manual conversions)
                    // Since Lead is manually converted (not using Salesforce's standard conversion),
                    // ConvertedAccountId might not be set, so we match by Company name
                    List<Account> accounts = [SELECT Name, CreatedDate FROM Account WHERE Id = :accountId LIMIT 1];
                    if (!accounts.isEmpty()) {
                        Account acc = accounts[0];
                        System.debug('Account Name: ' + acc.Name + ', Created: ' + acc.CreatedDate);
                        
                        // Find Lead by Company name - check Leads created within 30 minutes of Account creation
                        // This gives us a wider window to find the Lead
                        DateTime accountCreated = acc.CreatedDate;
                        DateTime leadSearchStart = accountCreated.addMinutes(-10);
                        DateTime leadSearchEnd = accountCreated.addMinutes(30);
                        
                        // First, try exact Company name match
                        List<Lead> matchingLeads = [
                            SELECT Id, Company, CreatedDate, ConvertedAccountId, IsConverted, Email
                            FROM Lead 
                            WHERE Company = :acc.Name 
                            AND CreatedDate >= :leadSearchStart
                            AND CreatedDate <= :leadSearchEnd
                            ORDER BY CreatedDate DESC 
                            LIMIT 10
                        ];
                        
                        System.debug('Found ' + matchingLeads.size() + ' Leads matching Account name and creation time');
                        for (Lead l : matchingLeads) {
                            System.debug('  Lead: ' + l.Id + ', Company: ' + l.Company + ', ConvertedAccountId: ' + l.ConvertedAccountId + ', IsConverted: ' + l.IsConverted + ', Email: ' + l.Email);
                        }
                        
                        // Prefer Lead that hasn't been converted yet (IsConverted = false)
                        // Since we're doing manual conversion, the Lead should still exist and not be marked as converted
                        for (Lead l : matchingLeads) {
                            if (!l.IsConverted && l.ConvertedAccountId == null) {
                                leadId = l.Id;
                                System.debug('✓ Selected Lead (not converted): ' + leadId);
                                break;
                            }
                        }
                        
                        // If no unconverted Lead found, use the most recent one
                        if (leadId == null && !matchingLeads.isEmpty()) {
                            leadId = matchingLeads[0].Id;
                            System.debug('✓ Using most recent Lead: ' + leadId);
                        }
                    }
                    
                    // Strategy 2: If still not found, try ConvertedAccountId lookup (in case it was set)
                    if (leadId == null) {
                        List<Lead> convertedLeads = [
                            SELECT Id, Company, ConvertedAccountId, IsConverted
                            FROM Lead 
                            WHERE ConvertedAccountId = :accountId 
                            LIMIT 1
                        ];
                        if (!convertedLeads.isEmpty()) {
                            leadId = convertedLeads[0].Id;
                            System.debug('✓ Found Lead by ConvertedAccountId: ' + leadId);
                        }
                    }
                    
                    // Strategy 3: Last resort - find any Lead with matching Company name (no time restriction)
                    if (leadId == null && !accounts.isEmpty()) {
                        List<Lead> anyMatchingLeads = [
                            SELECT Id, Company, CreatedDate, ConvertedAccountId, IsConverted
                            FROM Lead 
                            WHERE Company = :accounts[0].Name 
                            AND IsConverted = false
                            ORDER BY CreatedDate DESC 
                            LIMIT 1
                        ];
                        if (!anyMatchingLeads.isEmpty()) {
                            leadId = anyMatchingLeads[0].Id;
                            System.debug('✓ Found Lead by Company name (no time restriction): ' + leadId);
                        }
                    }
                    
                    if (leadId == null) {
                        String errorMsg = 'CRITICAL ERROR: Could not find Lead for Account ' + accountId + '. ';
                        errorMsg += 'The Order must have Lead__c set for new registrations. ';
                        errorMsg += 'Without Lead__c, payment processing cannot create a new user. ';
                        errorMsg += 'Please check that the Lead exists and was not deleted.';
                        System.debug('❌❌❌ ' + errorMsg);
                        throw new AuraHandledException(errorMsg);
                    } else {
                        System.debug('✓ SUCCESS: Found Lead ' + leadId + ' for Account ' + accountId);
                    }
                } catch (Exception e) {
                    System.debug('ERROR: Exception while looking up Lead: ' + e.getMessage());
                    System.debug('Stack trace: ' + e.getStackTraceString());
                    // Continue without leadId - this will cause it to be treated as renewal
                }
            }
            
            System.debug('Final leadId for Order creation: ' + leadId);
            System.debug('==========================================');
            
            // Check for existing order items - matches VF page (only if accountId exists)
            List<OrderItem> orderItems = new List<OrderItem>();
            if (accountId != null) {
                orderItems = [
                    SELECT OrderId
                    FROM OrderItem
                    WHERE Order.Status = 'Draft'
                    AND PricebookEntry.Product2.ProductCode = 'cer-membership-renewal'
                    AND Order.AccountId = :accountId
                ];
            }
            
            // If no existing order items, create new order - matches VF page
            if (orderItems == null || orderItems.size() == 0) {
                // IMPORTANT: Always use 'cer-membership' for new registrations
                // 'cer-membership-renewal' should ONLY be used when renewal is explicitly triggered from Account Administration
                // Since this is the Terms page (new registration flow), always use 'cer-membership'
                String productCode = 'cer-membership';
                System.debug('Using productCode "cer-membership" for new registration (Terms page flow)');
                System.debug('Note: "cer-membership-renewal" is only used when renewal button is clicked from Account Administration');
                
                List<PricebookEntry> pbeList = [
                    SELECT UnitPrice, Pricebook2Id
                    FROM PricebookEntry
                    WHERE Product2.ProductCode = :productCode
                    AND Pricebook2.Name = 'Standard Price Book'
                    LIMIT 1
                ];
                
                if (pbeList.isEmpty()) {
                    throw new AuraHandledException('Unable to find registration fee product (Product Code: ' + productCode + '). Please contact support.');
                }
                
                PricebookEntry pbe = pbeList[0];
                
                // Get accountId - use 'New Membership Account' if accountId is null
                Id orderAccountId;
                if (accountId != null) {
                    orderAccountId = accountId;
                } else {
                    List<Account> tempAccounts = [
                        SELECT Id 
                        FROM Account 
                        WHERE Name = 'New Membership Account' 
                        LIMIT 1
                    ];
                    
                    if (tempAccounts.isEmpty()) {
                        // Create "New Membership Account" if it doesn't exist
                        Account tempAccount = new Account(Name = 'New Membership Account');
                        try {
                            Database.insert(tempAccount);
                            orderAccountId = tempAccount.Id;
                        } catch (DmlException dmlEx) {
                            String errorMsg = 'Error creating temporary account: ';
                            if (dmlEx.getNumDml() > 0) {
                                errorMsg = dmlEx.getDmlMessage(0);
                            } else {
                                errorMsg += dmlEx.getMessage();
                            }
                            throw new AuraHandledException(errorMsg);
                        }
                    } else {
                        orderAccountId = tempAccounts[0].Id;
                    }
                }
                
                // Create Order - matches VF page exactly
                // CRITICAL: Lead__c must be set for new registrations so payment processing knows to create a user
                System.debug('===== CREATING ORDER =====');
                System.debug('Order AccountId: ' + orderAccountId);
                System.debug('Order Lead__c: ' + leadId);
                System.debug('ProductCode: ' + productCode);
                System.debug('Is New Registration: ' + (leadId != null));
                
                // CRITICAL: For new registrations (Terms page flow), leadId MUST be present
                // If leadId is null, we cannot create the Order because payment processing requires it
                if (leadId == null) {
                    String errorMsg = 'CRITICAL ERROR: Cannot create Order - leadId is NULL! ';
                    errorMsg += 'The Order must have Lead__c set for new registrations. ';
                    errorMsg += 'Without Lead__c, payment processing cannot create a new user and will fail. ';
                    errorMsg += 'Please ensure the Lead exists and the Lead lookup succeeded. ';
                    errorMsg += 'If you are testing, please complete the full registration flow from the beginning.';
                    System.debug('❌❌❌ ' + errorMsg);
                    throw new AuraHandledException(errorMsg);
                } else {
                    System.debug('✓ leadId is present: ' + leadId + ' - Order will be created with Lead__c');
                }
                
                Order o = new Order(
                    AccountId = orderAccountId,
                    EffectiveDate = System.today(),
                    Lead__c = leadId,  // CRITICAL: This must be set for new registrations
                    OwnerId = UserInfo.getUserId(),
                    Pricebook2Id = pbe.Pricebook2Id,
                    Status = 'Draft'
                );
                
                try {
                    Database.insert(o);
                    System.debug('Order created successfully with ID: ' + o.Id);
                    System.debug('Order.Lead__c after insert (from object): ' + o.Lead__c);
                    
                    // Verify Lead__c was set correctly by querying from database
                    List<Order> verifyOrders = [SELECT Id, Lead__c, AccountId FROM Order WHERE Id = :o.Id LIMIT 1];
                    if (!verifyOrders.isEmpty()) {
                        System.debug('VERIFICATION: Order.Lead__c (from database) = ' + verifyOrders[0].Lead__c);
                        System.debug('VERIFICATION: Order.AccountId (from database) = ' + verifyOrders[0].AccountId);
                        if (verifyOrders[0].Lead__c == null && leadId != null) {
                            System.debug('❌❌❌ ERROR: Lead__c was NOT set on Order despite leadId being provided!');
                            System.debug('❌❌❌ leadId provided: ' + leadId);
                            System.debug('❌❌❌ Order.Lead__c in database: ' + verifyOrders[0].Lead__c);
                        } else if (verifyOrders[0].Lead__c != null) {
                            System.debug('✓✓✓ SUCCESS: Order.Lead__c is set correctly: ' + verifyOrders[0].Lead__c);
                        }
                    } else {
                        System.debug('⚠️ WARNING: Could not verify Order after insert');
                    }
                    
                    orderIds.add(o.Id);
                } catch (DmlException dmlEx) {
                    String errorMsg = 'Error creating Order: ';
                    if (dmlEx.getNumDml() > 0) {
                        errorMsg = dmlEx.getDmlMessage(0);
                    } else {
                        errorMsg += dmlEx.getMessage();
                    }
                    throw new AuraHandledException(errorMsg);
                }
                
                // Create OrderItem - matches VF page exactly
                OrderItem oi = new OrderItem(
                    OrderId = o.Id,
                    PricebookEntryId = pbe.Id,
                    Quantity = 1,
                    UnitPrice = pbe.UnitPrice
                );
                
                try {
                    Database.insert(oi);
                } catch (DmlException dmlEx) {
                    String errorMsg = 'Error creating Order Item: ';
                    if (dmlEx.getNumDml() > 0) {
                        errorMsg = dmlEx.getDmlMessage(0);
                    } else {
                        errorMsg += dmlEx.getMessage();
                    }
                    // Try to delete the Order if OrderItem creation fails
                    try {
                        delete o;
                    } catch (Exception deleteEx) {
                        System.debug('Warning: Could not delete Order after OrderItem creation failure: ' + deleteEx.getMessage());
                    }
                    throw new AuraHandledException(errorMsg);
                }
            } else {
                // Use existing order items - matches VF page
                for (OrderItem oi : orderItems) {
                    orderIds.add(oi.OrderId);
                }
            }
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledException as-is
            throw e;
        } catch (Exception e) {
            String errorMsg = e.getMessage();
            if (String.isBlank(errorMsg)) {
                errorMsg = 'Error creating order. Please contact support.';
            } else {
                errorMsg = 'Error creating order: ' + errorMsg;
            }
            System.debug('Unexpected error in createOrder: ' + errorMsg);
            throw new AuraHandledException(errorMsg);
        }
        
        return new List<Id>(orderIds);
    }
    
    /**
     * Create Terms and Conditions record - if it doesn't exist
     */
    private static Id createTermsAndConditionsRecord(String siteName) {
        try {
            // Map site name to Site__c picklist value
            // Site.getMasterLabel() returns "CE Registry Portal" but Site__c might be "CE Provider"
            String siteValue = siteName;
            if (siteName.contains('CE Registry') || siteName == 'CE Registry Portal') {
                siteValue = 'CE Provider';
            } else if (siteName.contains('Massage License') || siteName == 'Massage License Verification Center') {
                siteValue = 'MT Verify';
                }
            
            System.debug('createTermsAndConditionsRecord - siteName: ' + siteName + ', mapped siteValue: ' + siteValue);
            
            // Check if Terms record already exists - try both siteName and mapped value
            List<Terms_and_Conditions__c> existingTerms = [
                SELECT Id, Terms_and_Conditions_Text__c, Site__c
                FROM Terms_and_Conditions__c
                WHERE (Site__c = :siteName OR Site__c = :siteValue)
                AND Activation_Date__c <= TODAY
                ORDER BY Activation_Date__c DESC, LastModifiedDate DESC
                LIMIT 1
            ];
            
            if (!existingTerms.isEmpty()) {
                // Use existing Terms record
                System.debug('Found existing Terms record: ' + existingTerms[0].Id + ' with Site__c: ' + existingTerms[0].Site__c);
                return existingTerms[0].Id;
            }
            
            // Fetch terms text from Custom Metadata
            String termsText = 'Terms and Conditions for ' + siteName + '. Please update this text as needed.';
            try {
                CE_Community_Content__mdt contentMdt = [
                    SELECT Registration__c
                    FROM CE_Community_Content__mdt
                    WHERE DeveloperName = 'Content'
                    LIMIT 1
                ];
                
                if (contentMdt.Registration__c != null && String.isNotBlank(contentMdt.Registration__c)) {
                    termsText = contentMdt.Registration__c;
            }
            } catch (Exception mdtException) {
                System.debug('Could not fetch terms from Custom Metadata: ' + mdtException.getMessage());
        }
            
            // Create new Terms and Conditions record - use mapped site value
            System.debug('Creating new Terms record with Site__c = ' + siteValue);
            Terms_and_Conditions__c newTerms = new Terms_and_Conditions__c(
                Site__c = siteValue,
                Terms_and_Conditions_Text__c = termsText,
                Activation_Date__c = Date.today()
            );
            
            insert newTerms;
            System.debug('Terms and Conditions record created: ' + newTerms.Id);
            return newTerms.Id;
            
        } catch (DmlException dmlEx) {
            String errorMsg = 'Error creating Terms and Conditions record: ';
            if (dmlEx.getNumDml() > 0) {
                errorMsg = dmlEx.getDmlMessage(0);
            } else {
                errorMsg += dmlEx.getMessage();
            }
            System.debug('DmlException creating Terms and Conditions: ' + errorMsg);
            throw new AuraHandledException(errorMsg);
        } catch (Exception e) {
            String errorMsg = e.getMessage();
            if (String.isBlank(errorMsg)) {
                errorMsg = 'Error creating Terms and Conditions record. Please contact support.';
            } else {
                errorMsg = 'Error creating Terms and Conditions: ' + errorMsg;
            }
            System.debug('Exception creating Terms and Conditions: ' + errorMsg);
            throw new AuraHandledException(errorMsg);
        }
    }
    
    /**
     * Create Terms and Conditions Acceptance record
     */
    private static void createTermsAcceptance(Id accountId, Id termsId, String siteName) {
        try {
            // Check if Acceptance already exists
            List<Terms_and_Conditions_Acceptance__c> existingAcceptance = [
                SELECT Id
                FROM Terms_and_Conditions_Acceptance__c
                WHERE Account__c = :accountId
                AND Terms_and_Conditions__c = :termsId
            LIMIT 1
        ];
        
            if (!existingAcceptance.isEmpty()) {
                System.debug('Terms Acceptance already exists for this Account and Terms');
            return;
        }
        
        // Create Terms and Conditions Acceptance
        Terms_and_Conditions_Acceptance__c acceptance = new Terms_and_Conditions_Acceptance__c(
            Account__c = accountId,
            Terms_Accepted_By__c = UserInfo.getUserId(),
                Terms_and_Conditions__c = termsId
        );
        
        insert acceptance;
        System.debug('Terms and Conditions Acceptance created: ' + acceptance.Id);
            
        } catch (DmlException dmlEx) {
            String errorMsg = 'Error creating Terms Acceptance: ';
            if (dmlEx.getNumDml() > 0) {
                errorMsg = dmlEx.getDmlMessage(0);
            } else {
                errorMsg += dmlEx.getMessage();
            }
            System.debug('DmlException creating Terms Acceptance: ' + errorMsg);
            throw new AuraHandledException(errorMsg);
        } catch (Exception e) {
            String errorMsg = e.getMessage();
            if (String.isBlank(errorMsg)) {
                errorMsg = 'Error creating Terms Acceptance. Please contact support.';
            } else {
                errorMsg = 'Error creating Terms Acceptance: ' + errorMsg;
            }
            System.debug('Exception creating Terms Acceptance: ' + errorMsg);
            throw new AuraHandledException(errorMsg);
        }
    }
    
    /**
     * Format terms text for HTML display
     */
    private static String formatTermsForHTML(String termsText) {
        if (String.isBlank(termsText)) {
            return '';
        }
        
        // Convert line breaks to HTML
        String formatted = termsText.replace('\n', '<br />');
        
        // Ensure proper HTML encoding
        return formatted;
    }
}
