public class AccountTriggerHandler extends TriggerHandler {
    private static final Set<String> PORTAL_CONTACTUSER_RECORDTYPES = new Set<String>{
            'SLB_User', 'MT_Verify_User'
    };
    private static final String CE_ADMINISTRATOR_PROFILE_NAME = 'CE Provider Administrator';
    private static final String MT_ADMINISTRATOR_PROFILE_NAME = 'MT Verify Administrator';
    
    // Status values - Membership Status
    private static final String MEMBERSHIP_ACTIVE = 'Active';
    private static final String MEMBERSHIP_LAPSED = 'Lapsed';
    private static final String MEMBERSHIP_INACTIVE = 'Inactive';
    private static final String MEMBERSHIP_EXPIRED = 'Expired';
    private static final String MEMBERSHIP_RENEWAL = 'Renewal';
    
    // Status values - Registration Status
    private static final String REGISTRATION_PROVISIONAL = 'Provisional';
    private static final String REGISTRATION_REGISTERED = 'Registered';
    
    // Thresholds for membership status
    private static final Integer EXPIRED_DAYS_THRESHOLD = 60; // Expired if > 60 days past expiration
    private static final Integer INACTIVE_DAYS_THRESHOLD = 30; // Inactive if > 30 days past expiration
    
    // Registration milestone threshold
    private static final Integer REGISTRATION_SURVEY_THRESHOLD = 50; // Registered if Survey_Total_Happy__c >= 50

    protected override void beforeInsert() {
        handleStatusCalculations();
        assignCeProviderNumbers();
        handleInsertUpdate();
    }

    protected override void beforeUpdate() {
        handleStatusCalculations();
        assignCeProviderNumbers();
        handleInsertUpdate();
    }

    protected override void afterUpdate() {
        Map<Id, RecordType> recordTypes = new Map<Id, RecordType>([
                SELECT Id, DeveloperName
                FROM RecordType
                WHERE DeveloperName IN ('CE_Provider', 'MT_Verify')
                AND SobjectType = 'Account'
        ]);

        List<Account> accounts_StatusChanged = new List<Account>();

        for (Account account : ((Map<Id, Account>) Trigger.newMap).values()) {
            if (account.Status__c != ((Account) Trigger.oldMap.get(account.Id)).Status__c && recordTypes.keySet().contains(account.RecordTypeId)) {
                accounts_StatusChanged.add(account);
            }
        }

        if (accounts_StatusChanged.size() > 0) updatePortalUsers(accounts_StatusChanged, recordTypes);
    }

    /**
     * Assign CE Provider Number (CERP-########) to CE Provider accounts that do not have one.
     * Uses MAX(CE_Provider_Number_Sequence__c) from Account; no Custom Setting required.
     */
    private void assignCeProviderNumbers() {
        Id ceProviderRtId;
        try {
            ceProviderRtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'CE_Provider' LIMIT 1].Id;
        } catch (QueryException e) {
            return;
        }
        for (Account acc : (List<Account>) Trigger.new) {
            if (acc.RecordTypeId == ceProviderRtId && String.isBlank(acc.CE_Provider_Number__c)) {
                CeProviderNumberService.NextCeProviderNumberResult result = CeProviderNumberService.getNextNumberAndSequence();
                acc.CE_Provider_Number__c = result.ceProviderNumber;
                acc.CE_Provider_Number_Sequence__c = result.sequenceNumber;
            }
        }
    }

    private void handleInsertUpdate() {
        Boolean resetFlags = stateParticipationFlagsNeedReset();

        //On insert of a new account with the BillingStateCode field populated or an update to BillingStateCode
        //all contacts with 'SLB Admin'/'SLB Search Only' record types need to have the pop up flag reset to true.
        if (resetFlags) {
            String recordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName IN :PORTAL_CONTACTUSER_RECORDTYPES AND SobjectType = 'Contact'][0].Id;

            List<Contact> contacts = [
                    SELECT Id, Display_State_Participation_Dialog__c
                    FROM Contact
                    WHERE RecordTypeId = :recordTypeId
            ];

            for (Contact contact : contacts) {
                contact.Display_State_Participation_Dialog__c = true;
            }

            update contacts;
        }
    }

    private Boolean stateParticipationFlagsNeedReset() {
        Boolean resetFlags = false;
        Map<Id, Account> newAccountMap = (Map<Id, Account>) Trigger.newMap;
        Map<Id, Account> oldAccountMap = (Map<Id, Account>) Trigger.oldMap;

        if (Trigger.isUpdate) {
            for (Account account : (List<Account>) Trigger.new) {
                if (!oldAccountMap.get(account.Id).Participating__c && newAccountMap.get(account.Id).Participating__c) {
                    resetFlags = true;
                    break;
                }
            }
        } else if (Trigger.isInsert) {
            for (Account account : (List<Account>) Trigger.new) {
                if (account.BillingStateCode != null && account.BillingStateCode.length() > 0 && account.Participating__c) {
                    resetFlags = true;
                    break;
                }
            }
        }
        return resetFlags;
    }

    private void updatePortalUsers(List<Account> accounts, Map<Id, RecordType> recordTypes) {
        Id mtRecordTypeId;
        for (RecordType rt : recordTypes.values()) if (rt.DeveloperName == 'MT_Verify') mtRecordTypeId = rt.Id;

        for (Account account : accounts) {


            System.debug(account.Status__c);


            if (account.RecordTypeId == mtRecordTypeId) {
                if (account.Status__c.equalsIgnoreCase('Renewal')) {
                    inactiveNonAdminUsers(account.Id);
                }
            } else {
                if (account.Status__c.equalsIgnoreCase('Registered') ||
                        account.Status__c.equalsIgnoreCase('Renewal')) {
                    activateAdminUsers(account.Id);
                } else if (account.Status__c.equalsIgnoreCase('Expired') ||
                        account.Status__c.equalsIgnoreCase('Revoked')) {
                    inactivateAllUsers(account.Id);
                } else if (account.Status__c.equalsIgnoreCase('Lapsed')) {
                    inactiveNonAdminUsers(account.Id);
                }
            }
        }
    }

    @Future
    private static void activateAdminUsers(Id accountId) {
        List<User> users = [
                SELECT IsActive
                FROM User
                WHERE AccountId = :accountId
                AND Profile.Name IN (:CE_ADMINISTRATOR_PROFILE_NAME, :MT_ADMINISTRATOR_PROFILE_NAME)
                AND Removed_From_Communities__c = FALSE
        ];
        for (User user : users) user.IsActive = true;
        update users;
    }

    @Future
    private static void inactivateAllUsers(Id accountId) {
        List<User> users = [
                SELECT IsActive
                FROM User
                WHERE AccountId = :accountId
                AND Removed_From_Communities__c = FALSE
        ];
        for (User user : users) user.IsActive = false;
        update users;
    }

    @Future
    private static void inactiveNonAdminUsers(Id accountId) {
        List<User> users = [
                SELECT IsActive
                FROM User
                WHERE AccountId = :accountId
                AND Profile.Name NOT IN (:CE_ADMINISTRATOR_PROFILE_NAME, :MT_ADMINISTRATOR_PROFILE_NAME)
                AND Removed_From_Communities__c = FALSE
        ];
        for (User user : users) user.IsActive = false;
        update users;
    }
    
    /**
     * Handle status calculations for Membership Status and Registration Status
     */
    private void handleStatusCalculations() {
        Map<Id, Account> oldMap = Trigger.oldMap != null ? (Map<Id, Account>) Trigger.oldMap : new Map<Id, Account>();
        
        // Cache RecordTypes to avoid SOQL in loop
        Set<Id> recordTypeIds = new Set<Id>();
        for (Account acc : (List<Account>) Trigger.new) {
            if (acc.RecordTypeId != null) {
                recordTypeIds.add(acc.RecordTypeId);
            }
        }
        
        Map<Id, String> recordTypeDevNameMap = new Map<Id, String>();
        if (!recordTypeIds.isEmpty()) {
            for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE Id IN :recordTypeIds AND SobjectType = 'Account']) {
                recordTypeDevNameMap.put(rt.Id, rt.DeveloperName);
            }
        }
        
        for (Account acc : (List<Account>) Trigger.new) {
            Account oldAcc = oldMap.get(acc.Id);
            
            // Set default values for new accounts
            if (Trigger.isInsert) {
                if (acc.Membership_Status__c == null) {
                    acc.Membership_Status__c = MEMBERSHIP_ACTIVE; // Default to Active
                }
                
                // Only set default to Provisional if Registration_Status__c is null
                // IMPORTANT: During registration (before payment), we want to keep it as null
                // so it can be set to 'Provisional' after payment is completed
                // We'll check if this is a new registration by checking if Portal_Account_Owner__c is null
                // (new registrations won't have a Portal_Account_Owner__c until after payment)
                if (acc.Registration_Status__c == null && acc.Portal_Account_Owner__c != null) {
                    // Only set to Provisional if Account already has an owner (not a new registration)
                    acc.Registration_Status__c = REGISTRATION_PROVISIONAL;
                }
                // If Registration_Status__c is null and Portal_Account_Owner__c is also null,
                // this is likely a new registration before payment - keep it as null
            }
            
            // Calculate membership status if relevant fields changed or on insert
            if (Trigger.isInsert || needsMembershipStatusRecalculation(acc, oldAcc)) {
                calculateMembershipStatusStatic(acc, recordTypeDevNameMap);
            }
            
            // Calculate registration status if survey count changed or on insert
            if (Trigger.isInsert || needsRegistrationStatusRecalculation(acc, oldAcc)) {
                calculateRegistrationStatusStatic(acc);
            }
        }
    }
    
    /**
     * Calculate Membership Status based on Membership_Expiration_Date__c and Allow_Renewal__c
     */
    private static void calculateMembershipStatusStatic(Account acc, Map<Id, String> recordTypeDevNameMap) {
        String recordTypeDevName = recordTypeDevNameMap != null && acc.RecordTypeId != null 
            ? recordTypeDevNameMap.get(acc.RecordTypeId) 
            : null;
        
        if (recordTypeDevName == 'CE_Provider') {
            // CE Provider logic
            if (acc.Allow_Renewal__c == true) {
                acc.Membership_Status__c = MEMBERSHIP_RENEWAL;
            } else if (acc.Membership_Expiration_Date__c != null) {
                Integer daysDiff = System.today().daysBetween(acc.Membership_Expiration_Date__c);
                
                if (daysDiff <= -EXPIRED_DAYS_THRESHOLD) {
                    // Expired if expiration date is 60+ days ago
                    acc.Membership_Status__c = MEMBERSHIP_EXPIRED;
                } else if (daysDiff <= -INACTIVE_DAYS_THRESHOLD) {
                    // Inactive if expiration date is 30-59 days ago
                    acc.Membership_Status__c = MEMBERSHIP_INACTIVE;
                } else if (daysDiff < 0) {
                    // Lapsed if expiration date is 1-29 days ago
                    acc.Membership_Status__c = MEMBERSHIP_LAPSED;
                } else {
                    // Active if expiration date is today or in the future
                    acc.Membership_Status__c = MEMBERSHIP_ACTIVE;
                }
            } else {
                // No expiration date - default to Active
                acc.Membership_Status__c = MEMBERSHIP_ACTIVE;
            }
        } else if (recordTypeDevName == 'MT_Verify') {
            // MT Verify logic
            if (acc.Membership_Expiration_Date__c != null) {
                Integer daysDiff = System.today().daysBetween(acc.Membership_Expiration_Date__c);
                
                if (daysDiff < 0) {
                    // Renewal if expired
                    acc.Membership_Status__c = MEMBERSHIP_RENEWAL;
                } else {
                    // Active if not expired
                    acc.Membership_Status__c = MEMBERSHIP_ACTIVE;
                }
            } else {
                // No expiration date - default to Active
                acc.Membership_Status__c = MEMBERSHIP_ACTIVE;
            }
        } else {
            // Other record types - default to Active
            if (acc.Membership_Status__c == null) {
                acc.Membership_Status__c = MEMBERSHIP_ACTIVE;
            }
        }
    }
    
    /**
     * Calculate Registration Status based on Survey_Total_Happy__c
     */
    private static void calculateRegistrationStatusStatic(Account acc) {
        Decimal surveyTotalHappy = acc.Survey_Total_Happy__c != null ? acc.Survey_Total_Happy__c : 0;
        
        if (surveyTotalHappy >= REGISTRATION_SURVEY_THRESHOLD) {
            // Reached milestone - set to Registered
            Boolean wasNotRegistered = (acc.Registration_Status__c != REGISTRATION_REGISTERED);
            
            acc.Registration_Status__c = REGISTRATION_REGISTERED;
            acc.Registration_Status_Flag__c = true;
            
            // Capture date when milestone was reached (only set once)
            if (wasNotRegistered && acc.Registration_Status_Date__c == null) {
                acc.Registration_Status_Date__c = System.today();
            }
        } else {
            // Below threshold - set to Provisional
            acc.Registration_Status__c = REGISTRATION_PROVISIONAL;
            acc.Registration_Status_Flag__c = false;
            
            // Note: Don't clear Registration_Status_Date__c to maintain historical record
        }
    }
    
    /**
     * Check if membership status needs recalculation
     */
    private Boolean needsMembershipStatusRecalculation(Account newAcc, Account oldAcc) {
        if (oldAcc == null) {
            return true; // New record
        }
        
        return (
            newAcc.Membership_Expiration_Date__c != oldAcc.Membership_Expiration_Date__c ||
            newAcc.Allow_Renewal__c != oldAcc.Allow_Renewal__c ||
            newAcc.RecordTypeId != oldAcc.RecordTypeId ||
            // Recalculate daily for accounts with expiration dates in the past
            (newAcc.Membership_Expiration_Date__c != null && newAcc.Membership_Expiration_Date__c < System.today())
        );
    }
    
    /**
     * Check if registration status needs recalculation
     */
    private Boolean needsRegistrationStatusRecalculation(Account newAcc, Account oldAcc) {
        if (oldAcc == null) {
            return true; // New record
        }
        
        // Recalculate if survey count changed
        return (newAcc.Survey_Total_Happy__c != oldAcc.Survey_Total_Happy__c);
    }
    
    /**
     * Batch method to recalculate all account statuses (for migration or scheduled job)
     * Can be called from Anonymous Apex or other classes
     */
    public static void recalculateAllAccountStatuses(List<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }
        
        List<Account> accountsToUpdate = [
            SELECT Id, RecordTypeId, Membership_Expiration_Date__c, Allow_Renewal__c, 
                   Survey_Total_Happy__c, Membership_Status__c, Registration_Status__c,
                   Registration_Status_Date__c, Registration_Status_Flag__c
            FROM Account
            WHERE Id IN :accountIds
        ];
        
        // Cache RecordTypes for migration batch
        Set<Id> recordTypeIds = new Set<Id>();
        for (Account acc : accountsToUpdate) {
            if (acc.RecordTypeId != null) {
                recordTypeIds.add(acc.RecordTypeId);
            }
        }
        
        Map<Id, String> recordTypeDevNameMap = new Map<Id, String>();
        if (!recordTypeIds.isEmpty()) {
            for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE Id IN :recordTypeIds AND SobjectType = 'Account']) {
                recordTypeDevNameMap.put(rt.Id, rt.DeveloperName);
            }
        }
        
        for (Account acc : accountsToUpdate) {
            // Use static methods that can be called from static context
            calculateMembershipStatusStatic(acc, recordTypeDevNameMap);
            calculateRegistrationStatusStatic(acc);
        }
        
        if (!accountsToUpdate.isEmpty()) {
            Database.update(accountsToUpdate, false); // Allow partial success
        }
    }
}