public with sharing class OrgRegistryController {

    // Wrapper to return both Account & Contact Ids and status
    public class CreationResult {
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    // Wrapper for Terms acceptance result
    public class TermsResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Id termsId { get; set; }
        @AuraEnabled public Id acceptanceId { get; set; }
    }

    // Wrapper for Account update + Order creation result
    public class AccountOrderResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Account updatedAccount { get; set; }
        @AuraEnabled public Id orderId { get; set; }
    }

    // Wrapper for state picklist options
    public class StateOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    // Create Account & Contact
    @AuraEnabled
    public static CreationResult createAccountAndContact(Map<String, String> formValues) {
        CreationResult result = new CreationResult();
        try {
            if(formValues == null || formValues.isEmpty()) {
                result.success = false;
                result.message = 'Form values are empty';
                return result;
            }

            RecordType accRT = [SELECT Id FROM RecordType WHERE SObjectType='Account' AND DeveloperName='CE_Provider' LIMIT 1];
            RecordType conRT = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='CE_Provider_User' LIMIT 1];

            if(accRT == null) {
                result.success = false;
                result.message = 'Account RecordType CE_Provider not found';
                return result;
            }
            if(conRT == null) {
                result.success = false;
                result.message = 'Contact RecordType CE_Provider_User not found';
                return result;
            }

            // Validate required fields
            if(String.isBlank(formValues.get('businessName'))) {
                result.success = false;
                result.message = 'Business Name is required to create Account';
                return result;
            }
            if(String.isBlank(formValues.get('lastName'))) {
                result.success = false;
                result.message = 'Last Name is required to create Contact';
                return result;
            }

            // Check if account with same name exists
            List<Account> existingAccs = [SELECT Id FROM Account WHERE Name = :formValues.get('businessName') LIMIT 1];
            if (!existingAccs.isEmpty()) {
                result.success = false;
                result.message = 'The Provider Name already exists in our system. Please provide a new name or contact FSMTB at  CE@fsmtb.org  with questions.';
                return result;
            }

            String websiteUrl = formValues.get('website');
            if(!String.isBlank(websiteUrl) && 
               !websiteUrl.startsWithIgnoreCase('http://') &&
               !websiteUrl.startsWithIgnoreCase('https://')) {
                websiteUrl = 'https://' + websiteUrl;
            }

            Account acc = new Account(
                Name = formValues.get('businessName'),
                RecordTypeId = accRT.Id,
                Phone = formValues.get('businessPhone'),
                Fax = formValues.get('fax'),
                Website = websiteUrl,
                BillingStreet = formValues.get('businessAddress1') 
                                + (formValues.get('businessAddress2') != null ? ', ' + formValues.get('businessAddress2') : ''),
                BillingCity = formValues.get('city'),
                BillingState = formValues.get('state'),
                BillingPostalCode = formValues.get('zip')
            );
            insert acc;

            Contact con = new Contact(
                AccountId = acc.Id,
                RecordTypeId = conRT.Id,
                FirstName = formValues.get('firstName'),
                LastName = formValues.get('lastName'),
                Email = formValues.get('ownerEmail'),
                Phone = formValues.get('ownerPhone'),
                Title = formValues.get('title'),
                Portal_Username__c = formValues.get('username')
            );
            insert con;

            result.accountId = acc.Id;
            result.contactId = con.Id;
            result.success = true;
            result.message = 'Account & Contact created successfully';

        } catch(Exception e) {
            result.success = false;
            result.message = 'Error creating Account & Contact: ' + e.getMessage();
        }

        return result;
    }

    // Accept Terms & Conditions
    @AuraEnabled
    public static TermsResult acceptTerms(Id accountId) {
        TermsResult result = new TermsResult();
        try {
            if(accountId == null) {
                result.success = false;
                result.message = 'Account Id is required to accept Terms';
                return result;
            }

            // Create Terms_and_Conditions__c
            Terms_and_Conditions__c terms = new Terms_and_Conditions__c(
                Activation_Date__c = Date.today(),
                Site__c = 'CE Registry'
            );
            insert terms;

            // Create Terms_and_Conditions_Acceptance__c
            Terms_and_Conditions_Acceptance__c acceptance = new Terms_and_Conditions_Acceptance__c(
                Account__c = accountId,
                Terms_Accepted_By__c = UserInfo.getUserId(),
                Terms_and_Conditions__c = terms.Id
            );
            insert acceptance;

            // Return IDs
            result.success = true;
            result.message = 'Terms accepted successfully';
            result.termsId = terms.Id;
            result.acceptanceId = acceptance.Id;

        } catch(Exception e) {
            result.success = false;
            result.message = 'Error accepting Terms: ' + e.getMessage();
        }

        return result;
    }

    // Get Account Details
    @AuraEnabled(cacheable=true)
    public static Account getAccountDetails(Id accountId) {
        if (String.isBlank(accountId)) {
            return null;
        }
        return [
            SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingStateCode, BillingPostalCode,
                   Phone, Fax, Website, Email__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
    }

    // Get Account Details for the currently logged in user's Account
    // Used by the renewal LWC when launched from the community without an explicit Account Id
    @AuraEnabled(cacheable=true)
    public static Account getCurrentUserAccountDetails() {
        try {
            User u = [
                SELECT AccountId
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            if (u.AccountId == null) {
                return null;
            }

            // Use helper class to bypass sharing restrictions for querying
            // This ensures we can read all fields even if sharing rules restrict access
            Account acc = AccountUpdateHelper.getAccountById(u.AccountId);
            return acc;
        } catch (Exception e) {
            // Swallow and return null so the client can handle gracefully
            System.debug('Error in getCurrentUserAccountDetails: ' + e.getMessage());
            return null;
        }
    }

    // Update Account
    @AuraEnabled
    public static Account updateAccount(Account acc) {
        if (acc == null || acc.Id == null) {
            throw new AuraHandledException('Invalid account data.');
        }
        update acc;
        return [
            SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode,
                   Phone, Fax, Website, Email__c
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
    }

    // Update Account and Create Order 
    @AuraEnabled
    public static AccountOrderResult updateAccountAndCreateOrder(Account acc) {
        AccountOrderResult result = new AccountOrderResult();
        try {
            if (acc == null || acc.Id == null) {
                result.success = false;
                result.message = 'Invalid account data';
                return result;
            }

            // Basic validation similar to legacy VF renewal validation
            List<String> errors = new List<String>();

            if (String.isBlank(acc.Email__c) || !acc.Email__c.contains('@') || !acc.Email__c.contains('.')) {
                errors.add('Active email is required and must be formatted as an email address.');
            }
            if (String.isBlank(acc.BillingStreet)) {
                errors.add('Address is required.');
            }
            if (String.isBlank(acc.BillingCity)) {
                errors.add('City is required.');
            }
            if (String.isBlank(acc.BillingPostalCode)) {
                errors.add('Zip code is required.');
            }
            if (String.isBlank(acc.Phone)) {
                errors.add('Telephone number is required.');
            }

            if (!errors.isEmpty()) {
                result.success = false;
                result.message = String.join(errors, ' ');
                return result;
            }

            // Verify user has access to this Account by checking if it's their associated Account
            User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            if (currentUser.AccountId != acc.Id) {
                result.success = false;
                result.message = 'You do not have permission to update this account.';
                return result;
            }

            // Query the Account using helper class (without sharing) to get current values
            // We've already verified the user is associated with this Account above
            Account accountToUpdate = AccountUpdateHelper.getAccountById(acc.Id);
            
            if (accountToUpdate == null) {
                result.success = false;
                result.message = 'Account not found.';
                return result;
            }
            
            // Update only the fields that are provided (and that user has permission to update)
            if (acc.Email__c != null) {
                accountToUpdate.Email__c = acc.Email__c;
            }
            if (acc.BillingStreet != null) {
                accountToUpdate.BillingStreet = acc.BillingStreet;
            }
            if (acc.BillingCity != null) {
                accountToUpdate.BillingCity = acc.BillingCity;
            }
            if (acc.BillingStateCode != null) {
                accountToUpdate.BillingStateCode = acc.BillingStateCode;
            }
            if (acc.BillingPostalCode != null) {
                accountToUpdate.BillingPostalCode = acc.BillingPostalCode;
            }
            if (acc.Phone != null) {
                accountToUpdate.Phone = acc.Phone;
            }
            if (acc.Fax != null) {
                accountToUpdate.Fax = acc.Fax;
            }
            if (acc.Website != null) {
                accountToUpdate.Website = acc.Website;
            }

            // Update the Account using helper class (without sharing) to bypass sharing restrictions
            // This is safe because we verified the user is associated with this Account above
            Database.SaveResult saveResult = AccountUpdateHelper.updateAccount(accountToUpdate);
            if (!saveResult.isSuccess()) {
                String errorMsg = 'Error updating account: ';
                for (Database.Error err : saveResult.getErrors()) {
                    errorMsg += err.getMessage() + ' ';
                    // Check for specific permission errors
                    if (err.getStatusCode() == StatusCode.INSUFFICIENT_ACCESS_OR_READONLY) {
                        errorMsg += 'You do not have permission to update this account. Please contact your administrator. ';
                    }
                }
                result.success = false;
                result.message = errorMsg.trim();
                return result;
            }

            // Get PricebookEntry for renewal product
            // Try 'cer-membership-renewal' first, fallback to 'CE_RENEWAL' or 'cer-membership'
            PricebookEntry pbe;
            String productCode = 'cer-membership-renewal';
            
            try {
                pbe = [
                    SELECT Id, UnitPrice, Pricebook2Id, Product2.ProductCode
                    FROM PricebookEntry
                    WHERE Product2.ProductCode = :productCode
                    AND Pricebook2.Name = 'Standard Price Book'
                    AND IsActive = true
                    LIMIT 1
                ];
            } catch (Exception e) {
                // Try alternative product codes
                try {
                    pbe = [
                        SELECT Id, UnitPrice, Pricebook2Id, Product2.ProductCode
                        FROM PricebookEntry
                        WHERE Product2.ProductCode = 'CE_RENEWAL'
                        AND Pricebook2.Name = 'Standard Price Book'
                        AND IsActive = true
                        LIMIT 1
                    ];
                } catch (Exception e2) {
                    // Final fallback
                    try {
                        pbe = [
                            SELECT Id, UnitPrice, Pricebook2Id, Product2.ProductCode
                            FROM PricebookEntry
                            WHERE Product2.ProductCode = 'cer-membership'
                            AND Pricebook2.Name = 'Standard Price Book'
                            AND IsActive = true
                            LIMIT 1
                        ];
                    } catch (Exception e3) {
                        result.success = false;
                        result.message = 'Unable to find renewal fee product. Please contact support.';
                        return result;
                    }
                }
            }

            // Create Order attached to this Account with Pricebook
            Order ord = new Order(
                AccountId = acc.Id,
                EffectiveDate = Date.today(),
                Status = 'Draft',
                Pricebook2Id = pbe.Pricebook2Id,
                OwnerId = UserInfo.getUserId()
            );
            insert ord;

            // Create OrderItem for renewal
            OrderItem oi = new OrderItem(
                OrderId = ord.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = pbe.UnitPrice
            );
            insert oi;

            // Return updated account and order Id
            result.updatedAccount = [SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingStateCode, BillingPostalCode,
                                            Phone, Fax, Website, Email__c
                                     FROM Account WHERE Id = :acc.Id LIMIT 1];
            result.orderId = ord.Id;
            result.success = true;
            result.message = 'Account updated and Order created successfully';

        } catch(Exception e) {
            result.success = false;
            result.message = 'Error: ' + e.getMessage();
        }
        return result;
    }

    // Get state picklist (for BillingStateCode)
    @AuraEnabled(cacheable=true)
    public static List<StateOption> getStatePicklist() {
        List<StateOption> options = new List<StateOption>();
        Schema.DescribeFieldResult fieldResult = Account.BillingStateCode.getDescribe();
        for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
            StateOption so = new StateOption();
            so.label = entry.getLabel();
            so.value = entry.getValue();
            options.add(so);
        }
        return options;
    }

    // Get renewal content from custom metadata (mirrors VF "content" getter for isRenewal)
    @AuraEnabled(cacheable=true)
    public static String getRenewalContent() {
        try {
            CE_Community_Content__mdt content = [
                SELECT Renewal__c
                FROM CE_Community_Content__mdt
                WHERE DeveloperName = 'Content'
                LIMIT 1
            ];
            if (content.Renewal__c == null) {
                return '';
            }
            // If CommunityUtil is available, format HTML like VF
            try {
                return CommunityUtil.formatContentForHTML(content.Renewal__c);
            } catch (Exception e) {
                // Fallback to raw HTML if utility is not available
                return content.Renewal__c;
            }
        } catch (Exception e) {
            return '';
        }
    }

    /**
     * Check if renewal was already completed by checking for future Membership records
     * Only returns true if a future Membership__c record exists (Start_Date__c > TODAY)
     */
    @AuraEnabled
    public static Boolean checkRenewalStatus(Id accountId) {
        if (accountId == null) {
            return false;
        }
        
        try {
            // Check if there's a future Membership record (Start_Date__c > TODAY)
            // This indicates renewal is already complete
            List<Membership__c> futureMemberships = [
                SELECT Id, Start_Date__c
                FROM Membership__c 
                WHERE Account__c = :accountId 
                AND Start_Date__c > :Date.today()
                ORDER BY Start_Date__c ASC
                LIMIT 1
            ];
            
            return !futureMemberships.isEmpty();
        } catch (Exception e) {
            System.debug('Error checking renewal status: ' + e.getMessage());
            return false;
        }
    }

}