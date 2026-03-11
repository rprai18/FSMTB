// Use without sharing for guest user registration - guest users need to create Leads, Accounts, and Contacts
public without sharing class CeProviderRegistrationLwcController {

    // Local copy of CE username suffix used when building portal admin username
    // NOTE: Must match the community username domain used for CE Provider users
    private static final String CE_USERNAME_SUFFIX = '@ceprovider.fsmtb.org';

    // Wrapper for state options
    public class StateOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    // Wrapper for initial data (content + state picklist)
    public class RegistrationInitResult {
        @AuraEnabled public String content { get; set; }
        @AuraEnabled public List<StateOption> statePicklist { get; set; }
    }

    // Wrapper for proceed() result, mirroring VF error flags
    public class ProceedResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Id leadId { get; set; }
        @AuraEnabled public Id accountId { get; set; } // Account created from Lead
        @AuraEnabled public Id contactId { get; set; } // Contact created from Lead

        // Error flags - same semantics as CEProviderRegistrationController
        @AuraEnabled public Boolean displayBusinessNameError { get; set; }
        @AuraEnabled public Boolean displayBusinessNameDuplicationError { get; set; }
        @AuraEnabled public Boolean displayBusinessEmailError { get; set; }
        @AuraEnabled public Boolean displayBusinessEmailReenterError { get; set; }
        @AuraEnabled public Boolean displayBusinessAddressError { get; set; }
        @AuraEnabled public Boolean displayCityError { get; set; }
        @AuraEnabled public Boolean displayZipError { get; set; }
        @AuraEnabled public Boolean displayBusinessPhoneError { get; set; }
        @AuraEnabled public Boolean displayFirstNameError { get; set; }
        @AuraEnabled public Boolean displayLastNameError { get; set; }
        @AuraEnabled public Boolean displayUsernameError { get; set; }
        @AuraEnabled public Boolean displayEmailError { get; set; }
        @AuraEnabled public Boolean displayEmailReenterError { get; set; }
        @AuraEnabled public Boolean displayPhoneError { get; set; }
        @AuraEnabled public Boolean displayWebsiteError { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static RegistrationInitResult getInitData() {
        RegistrationInitResult res = new RegistrationInitResult();

        // Load registration content from custom metadata (same as VF when !isRenewal)
        try {
            CE_Community_Content__mdt mdt = [
                SELECT Registration__c
                FROM CE_Community_Content__mdt
                WHERE DeveloperName = 'Content'
                LIMIT 1
            ];
            if (mdt.Registration__c != null) {
                try {
                    res.content = CommunityUtil.formatContentForHTML(mdt.Registration__c);
                } catch (Exception e1) {
                    res.content = mdt.Registration__c;
                }
            } else {
                res.content = '';
            }
        } catch (Exception e) {
            res.content = '';
        }

        // Build state picklist (same source as Utils.statePicklist / BillingStateCode)
        res.statePicklist = new List<StateOption>();
        Schema.DescribeFieldResult dfr = Account.BillingStateCode.getDescribe();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            StateOption opt = new StateOption();
            opt.label = pe.getLabel();
            opt.value = pe.getValue();
            res.statePicklist.add(opt);
        }

        return res;
    }

    /**
     * Proceed with registration: validate fields and create Lead.
     *
     * formValues keys mirror the VF controller properties:
     * accountName, website, email, emailVerify, address1, address2,
     * city, state, postalCode, phone, fax,
     * ownerFirstName, ownerLastName, ownerUsername,
     * ownerEmail, ownerEmailVerify, ownerPhone, ownerTitle
     */
    @AuraEnabled
    public static ProceedResult proceed(Map<String, String> formValues) {
        ProceedResult res = new ProceedResult();
        if (formValues == null) {
            res.success = false;
            res.message = 'Form data is missing.';
            return res;
        }

        // Extract and normalize
        String accountName      = (formValues.get('accountName')      != null) ? formValues.get('accountName').trim()      : null;
        String website          = (formValues.get('website')          != null) ? formValues.get('website').trim()          : null;
        String email            = (formValues.get('email')            != null) ? formValues.get('email').trim()            : null;
        String emailVerify      = (formValues.get('emailVerify')      != null) ? formValues.get('emailVerify').trim()      : null;
        String address1         = (formValues.get('address1')         != null) ? formValues.get('address1').trim()         : null;
        String address2         = (formValues.get('address2')         != null) ? formValues.get('address2').trim()         : null;
        String city             = (formValues.get('city')             != null) ? formValues.get('city').trim()             : null;
        String state            = (formValues.get('state')            != null) ? formValues.get('state').trim()            : null;
        String postalCode       = (formValues.get('postalCode')       != null) ? formValues.get('postalCode').trim()       : null;
        String phone            = (formValues.get('phone')            != null) ? formValues.get('phone').trim()            : null;
        String fax              = (formValues.get('fax')              != null) ? formValues.get('fax').trim()              : null;
        String ownerFirstName   = (formValues.get('ownerFirstName')   != null) ? formValues.get('ownerFirstName').trim()   : null;
        String ownerLastName    = (formValues.get('ownerLastName')    != null) ? formValues.get('ownerLastName').trim()    : null;
        String ownerUsername    = (formValues.get('ownerUsername')    != null) ? formValues.get('ownerUsername').trim()    : null;
        String ownerEmail       = (formValues.get('ownerEmail')       != null) ? formValues.get('ownerEmail').trim()       : null;
        String ownerEmailVerify = (formValues.get('ownerEmailVerify') != null) ? formValues.get('ownerEmailVerify').trim() : null;
        String ownerPhone       = (formValues.get('ownerPhone')       != null) ? formValues.get('ownerPhone').trim()       : null;
        String ownerTitle       = (formValues.get('ownerTitle')       != null) ? formValues.get('ownerTitle').trim()       : null;

        Boolean valid = true;

        // Reset all error flags
        res.displayBusinessNameError = false;
        res.displayBusinessNameDuplicationError = false;
        res.displayBusinessEmailError = false;
        res.displayBusinessEmailReenterError = false;
        res.displayBusinessAddressError = false;
        res.displayCityError = false;
        res.displayZipError = false;
        res.displayBusinessPhoneError = false;
        res.displayFirstNameError = false;
        res.displayLastNameError = false;
        res.displayUsernameError = false;
        res.displayEmailError = false;
        res.displayEmailReenterError = false;
        res.displayPhoneError = false;
        res.displayWebsiteError = false;

        // Business name
        if (String.isBlank(accountName)) {
            valid = false;
            res.displayBusinessNameError = true;
        } else {
            // Check for duplicate Account name (case-insensitive, trimmed)
            String trimmedAccountName = accountName.trim();
            List<Account> existingAccounts = [
                SELECT Id, Name 
                FROM Account 
                WHERE Name = :trimmedAccountName 
                LIMIT 1
            ];
            if (!existingAccounts.isEmpty()) {
                valid = false;
                res.displayBusinessNameDuplicationError = true;
                res.message = 'The Provider Name already exists in our system. Please provide a new name or contact FSMTB at CE@fsmtb.org with questions.';
                // Return early to prevent any record creation
                res.success = false;
                return res;
            }
        }

        // Business email + re-enter
        if (String.isBlank(email) || email.containsNone('@') || email.containsNone('.')) {
            valid = false;
            res.displayBusinessEmailError = true;
        }
        if (!(email != null && email.equalsIgnoreCase(emailVerify))) {
            valid = false;
            res.displayBusinessEmailReenterError = true;
        }

        // Address 1
        if (String.isBlank(address1)) {
            valid = false;
            res.displayBusinessAddressError = true;
        }

        // City
        if (String.isBlank(city)) {
            valid = false;
            res.displayCityError = true;
        }

        // Postal code
        if (String.isBlank(postalCode)) {
            valid = false;
            res.displayZipError = true;
        }

        // Business phone
        if (String.isBlank(phone)) {
            valid = false;
            res.displayBusinessPhoneError = true;
        }

        // Business website - required
        if (String.isBlank(website)) {
            valid = false;
            res.displayWebsiteError = true;
        } else {
            // Basic website format validation
            String websiteTrimmed = website.trim();
            // Check if it's a valid URL format (must contain at least one dot and no spaces)
            if (!websiteTrimmed.contains('.') || websiteTrimmed.contains(' ')) {
                valid = false;
                res.displayWebsiteError = true;
            }
        }

        // Owner first/last
        if (String.isBlank(ownerFirstName)) {
            valid = false;
            res.displayFirstNameError = true;
        }
        if (String.isBlank(ownerLastName)) {
            valid = false;
            res.displayLastNameError = true;
        }

        // Owner username
        if (String.isBlank(ownerUsername) ||
            ownerUsername.containsWhitespace() ||
            ownerUsername.contains('@') ||
            [SELECT COUNT() FROM User WHERE Username = :ownerUsername + CE_USERNAME_SUFFIX] > 0) {

            valid = false;
            res.displayUsernameError = true;
        }

        // Owner email + re-enter
        if (String.isBlank(ownerEmail) || ownerEmail.containsNone('@') || ownerEmail.containsNone('.')) {
            valid = false;
            res.displayEmailError = true;
        }
        if (!(ownerEmail != null && ownerEmail.equalsIgnoreCase(ownerEmailVerify))) {
            valid = false;
            res.displayEmailReenterError = true;
        }

        // Owner phone
        if (String.isBlank(ownerPhone)) {
            valid = false;
            res.displayPhoneError = true;
        }

        if (!valid) {
            res.success = false;
            res.message = 'Please correct the highlighted errors and try again.';
            return res;
        }

        // If we get here, form is valid – create Lead exactly as VF controller
        try {
            // Ensure website starts with http:// or https:// if provided
            String formattedWebsite = website;
            if (String.isNotBlank(formattedWebsite) && 
                !formattedWebsite.startsWith('http://') && 
                !formattedWebsite.startsWith('https://')) {
                formattedWebsite = 'https://' + formattedWebsite;
            }
            
            Lead lead = new Lead(
                Company                = accountName,
                Website                = formattedWebsite,
                Email                  = email,
                Street                 = address1 + '\r\n' + (address2 != null ? address2 : ''),
                City                   = city,
                StateCode              = state,
                PostalCode             = postalCode,
                Phone                  = CommunityUtil.formatPhone(phone),
                Fax                    = fax,
                CountryCode            = 'US',
                LeadSource             = 'CE Registration',
                FirstName              = ownerFirstName,
                LastName               = ownerLastName,
                Portal_Admin_Username__c = ownerUsername + CE_USERNAME_SUFFIX,
                Portal_Admin_Email__c    = ownerEmail,
                Portal_Admin_Phone__c    = CommunityUtil.formatPhone(ownerPhone),
                Portal_Admin_Title__c    = ownerTitle
            );

            try {
            insert lead;
            } catch (DmlException dmlEx) {
                String errorMsg = 'Error creating Lead: ';
                if (dmlEx.getNumDml() > 0) {
                    errorMsg += dmlEx.getDmlMessage(0);
                    if (dmlEx.getDmlType(0) == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION) {
                        errorMsg = dmlEx.getDmlMessage(0); // Use the validation message directly
                    }
                } else {
                    errorMsg += dmlEx.getMessage();
                }
                res.success = false;
                res.message = errorMsg;
                System.debug('DML Exception creating Lead: ' + dmlEx.getMessage());
                return res;
            }

            // Immediately convert Lead to Account and Contact
            Id accountId;
            Id contactId;
            try {
                ConversionResult conversionResult = convertLeadToAccountAndContact(lead.Id);
                accountId = conversionResult.accountId;
                contactId = conversionResult.contactId;
            } catch (AuraHandledException auraEx) {
                // If conversion fails, try to delete the Lead
                try {
                    delete lead;
                } catch (Exception deleteEx) {
                    System.debug('Warning: Could not delete Lead after conversion failure: ' + deleteEx.getMessage());
                }
                res.success = false;
                res.message = auraEx.getMessage();
                System.debug('AuraHandledException in convertLeadToAccountAndContact: ' + auraEx.getMessage());
                return res;
            }

            res.leadId = lead.Id;
            res.accountId = accountId; // Return accountId for use in Terms page
            res.contactId = contactId; // Return contactId for use in payment processing
            res.success = true;
            res.message = 'Registration submitted successfully';
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledException as-is (shouldn't happen here, but just in case)
            res.success = false;
            String errorMsg = e.getMessage();
            if (String.isBlank(errorMsg)) {
                errorMsg = 'An error occurred during registration. Please contact support.';
            }
            res.message = errorMsg;
            System.debug('AuraHandledException in proceed: ' + errorMsg + ' Stack: ' + e.getStackTraceString());
        } catch (DmlException dmlEx) {
            res.success = false;
            String errorMsg = 'Error creating registration: ';
            if (dmlEx.getNumDml() > 0) {
                errorMsg = dmlEx.getDmlMessage(0);
            } else {
                errorMsg += dmlEx.getMessage();
            }
            res.message = errorMsg;
            System.debug('DmlException in proceed: ' + errorMsg + ' Stack: ' + dmlEx.getStackTraceString());
        } catch (Exception e) {
            res.success = false;
            String errorMsg = e.getMessage();
            if (String.isBlank(errorMsg)) {
                errorMsg = 'An unexpected error occurred during registration. Please try again or contact support.';
            } else {
                errorMsg = 'Error creating registration: ' + errorMsg;
            }
            res.message = errorMsg;
            System.debug('Unexpected exception in proceed: ' + errorMsg + ' Type: ' + e.getTypeName() + ' Stack: ' + e.getStackTraceString());
        }

        return res;
    }
    
    // Wrapper for conversion result
    private class ConversionResult {
        Id accountId;
        Id contactId;
    }
    
    /**
     * Convert Lead to Account and Contact - called immediately after Lead creation
     * Returns both AccountId and ContactId for use in payment processing
     */
    private static ConversionResult convertLeadToAccountAndContact(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead ID cannot be null for conversion.');
        }
        
        try {
            // Get Lead with all fields
            List<Lead> leadList = [
                SELECT Id, Company, Website, Email, Street, City, StateCode, PostalCode, Phone, Fax,
                       CountryCode, FirstName, LastName, Portal_Admin_Username__c, Portal_Admin_Email__c,
                       Portal_Admin_Phone__c, Portal_Admin_Title__c
                FROM Lead 
                WHERE Id = :leadId 
                LIMIT 1
            ];
            
            if (leadList.isEmpty()) {
                throw new AuraHandledException('Lead not found with ID: ' + leadId);
            }
            
            Lead lead = leadList[0];
            
            // Get Record Types with error handling
            List<RecordType> accRTList;
            List<RecordType> conRTList;
            
            try {
                accRTList = [
                    SELECT Id 
                    FROM RecordType 
                    WHERE SObjectType='Account' 
                    AND DeveloperName='CE_Provider' 
                    LIMIT 1
                ];
            } catch (QueryException qe) {
                System.debug('QueryException getting Account RecordType: ' + qe.getMessage());
                throw new AuraHandledException('Error retrieving Account Record Type. Please contact support.');
            }
            
            if (accRTList == null || accRTList.isEmpty()) {
                throw new AuraHandledException('Account Record Type "CE_Provider" not found. Please contact support.');
            }
            
            try {
                conRTList = [
                    SELECT Id 
                    FROM RecordType 
                    WHERE SObjectType='Contact' 
                    AND DeveloperName='CE_Provider_User' 
                    LIMIT 1
                ];
            } catch (QueryException qe) {
                System.debug('QueryException getting Contact RecordType: ' + qe.getMessage());
                throw new AuraHandledException('Error retrieving Contact Record Type. Please contact support.');
            }
            
            if (conRTList == null || conRTList.isEmpty()) {
                throw new AuraHandledException('Contact Record Type "CE_Provider_User" not found. Please contact support.');
            }
            
            RecordType accRT = accRTList[0];
            RecordType conRT = conRTList[0];
            
            // Ensure website starts with http:// or https:// if provided
            String formattedWebsite = null;
            if (String.isNotBlank(lead.Website)) {
                String websiteValue = lead.Website.trim();
                if (websiteValue.startsWithIgnoreCase('http://') || websiteValue.startsWithIgnoreCase('https://')) {
                    formattedWebsite = websiteValue;
                } else if (websiteValue.length() > 0) {
                    formattedWebsite = 'https://' + websiteValue;
                }
            }
            
            // Create Account
            Account acc = new Account(
                Name = lead.Company,
                RecordTypeId = accRT.Id,
                Phone = lead.Phone,
                Fax = lead.Fax,
                BillingStreet = lead.Street,
                BillingCity = lead.City,
                BillingStateCode = lead.StateCode,
                BillingPostalCode = lead.PostalCode,
                BillingCountryCode = lead.CountryCode != null ? lead.CountryCode : 'US',
                Email__c = lead.Email
            );
            
            // Only set Website if it's a valid URL (to avoid validation rule errors)
            if (formattedWebsite != null && String.isNotBlank(formattedWebsite)) {
                acc.Website = formattedWebsite;
            }
            
            try {
                insert acc;
            } catch (DmlException dmlEx) {
                String errorMsg = 'Error creating Account: ';
                if (dmlEx.getDmlType(0) == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION) {
                    errorMsg += dmlEx.getDmlMessage(0);
                } else {
                    errorMsg += dmlEx.getMessage();
                }
                throw new AuraHandledException(errorMsg);
            }
            
            // Create Contact
            Contact con = new Contact(
                AccountId = acc.Id,
                RecordTypeId = conRT.Id,
                FirstName = lead.FirstName,
                LastName = lead.LastName,
                Email = lead.Portal_Admin_Email__c,
                Phone = lead.Portal_Admin_Phone__c,
                Title = lead.Portal_Admin_Title__c,
                Portal_Username__c = lead.Portal_Admin_Username__c != null 
                    ? lead.Portal_Admin_Username__c.replace('@ceprovider.fsmtb.org', '') 
                    : null
            );
            
            try {
                insert con;
            } catch (DmlException dmlEx) {
                String errorMsg = 'Error creating Contact: ';
                if (dmlEx.getDmlType(0) == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION) {
                    errorMsg += dmlEx.getDmlMessage(0);
                } else {
                    errorMsg += dmlEx.getMessage();
                }
                // Try to delete the Account if Contact creation fails
                try {
                    delete acc;
                } catch (Exception deleteEx) {
                    System.debug('Error deleting Account after Contact creation failure: ' + deleteEx.getMessage());
                }
                throw new AuraHandledException(errorMsg);
            }
            
            // IMPORTANT: Do NOT delete the Lead here!
            // The Lead is needed later when creating the Order (to set Order.Lead__c)
            // The Lead will be deleted in CommunityOrderProcessor.processCerMembership() after payment processing
            // This ensures payment processing knows it's a new registration (not renewal)
            System.debug('Lead ' + lead.Id + ' will be kept until payment processing completes');
            
            System.debug('Lead converted to Account/Contact. Account ID: ' + acc.Id + ', Contact ID: ' + con.Id);
            
            // Return both AccountId and ContactId
            ConversionResult result = new ConversionResult();
            result.accountId = acc.Id;
            result.contactId = con.Id;
            return result;
            
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledException as-is
            String errorMsg = e.getMessage();
            if (String.isBlank(errorMsg)) {
                errorMsg = 'Error converting Lead to Account. Please contact support.';
            }
            System.debug('AuraHandledException in convertLeadToAccountAndContact: ' + errorMsg + ' Stack: ' + e.getStackTraceString());
            throw new AuraHandledException(errorMsg);
        } catch (DmlException dmlEx) {
            String errorMsg = 'Error creating Account or Contact: ';
            if (dmlEx.getNumDml() > 0) {
                errorMsg = dmlEx.getDmlMessage(0);
            } else {
                errorMsg += dmlEx.getMessage();
            }
            System.debug('DmlException in convertLeadToAccountAndContact: ' + errorMsg + ' Stack: ' + dmlEx.getStackTraceString());
            throw new AuraHandledException(errorMsg);
        } catch (Exception e) {
            String errorMsg = e.getMessage();
            if (String.isBlank(errorMsg)) {
                errorMsg = 'Unexpected error converting Lead to Account. Please contact support.';
            } else {
                errorMsg = 'Unexpected error converting Lead to Account: ' + errorMsg;
            }
            System.debug('Unexpected error converting Lead to Account: ' + errorMsg + ' Type: ' + e.getTypeName() + ' Stack: ' + e.getStackTraceString());
            throw new AuraHandledException(errorMsg);
        }
    }
}