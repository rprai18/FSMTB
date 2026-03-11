public without sharing class CommunityAdministrationLwcController {
    
    private static final String TOO_MANY_USERS_ERROR = 'There are too many active users!';
    // Must match CE provider username domain used during initial registration
    private static final String CE_USERNAME_SUFFIX = '@ceprovider.fsmtb.org';
    
    private static final Map<String, List<String>> AVAILABLE_PROFILES = new Map<String, List<String>> {
        'CE_Registry' => new List<String> {'CE Administrator', 'CE Courses & Rosters', 'CE Courses Only', 'CE Rosters Only'},
        'Massage_License_Verification_Center' => new List<String> {'MT Verify Administrator', 'MT Verify Search Only'}
    };
    
    @AuraEnabled(cacheable=true)
    public static AdministrationDataWrapper getAdministrationData() {
        AdministrationDataWrapper wrapper = new AdministrationDataWrapper();
        
        // Get current user info with profile
        User currentUser = [SELECT AccountId, Account.Name, Contact.RecordTypeId, Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Id userAccountId = currentUser.AccountId;
        String siteName = Site.getName();
        
        wrapper.accountId = userAccountId;
        wrapper.siteName = siteName != null ? siteName : 'CE_Registry';
        
        // Get account with UserRole information
        Account acc = [
            SELECT Name, Website, BillingStreet, BillingCity, BillingStateCode, BillingState, 
                   BillingPostalCode, Email__c, Phone, Fax, Portal_Account_Owner__c,
                   CE_Max_Portal_users__c, MT_Verify_Max_Portal_Users__c,
                   OwnerId, Owner.UserRoleId
            FROM Account WHERE Id = :userAccountId LIMIT 1
        ];
        wrapper.account = acc;
        
        // Get CE_Provider_User RecordType ID for Contact creation
        List<RecordType> contactRTList = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Contact' 
            AND DeveloperName = 'CE_Provider_User' 
            LIMIT 1
        ];
        wrapper.contactRecordTypeId = contactRTList.isEmpty() ? null : contactRTList[0].Id;
        
        // Get users
        List<User> allUsers = [
            SELECT Id, Username, CE_Provider_Username__c, FirstName, LastName, Email, Title, Phone,
                   ProfileId, Profile.Name, IsActive, Account.Portal_Account_Owner__c, CE_Registry_Alert__c
            FROM User 
            WHERE AccountId = :userAccountId 
            AND Removed_From_Communities__c = false 
            ORDER BY LastName
        ];
        
        wrapper.activeUsers = new List<UserWrapper>();
        wrapper.inactiveUsers = new List<UserWrapper>();
        
        Integer maxUsers = siteName == 'CE_Registry' ? 
            (acc.CE_Max_Portal_users__c != null ? Integer.valueOf(acc.CE_Max_Portal_users__c) : 3) :
            (acc.MT_Verify_Max_Portal_Users__c != null ? Integer.valueOf(acc.MT_Verify_Max_Portal_Users__c) : 3);
        
        wrapper.maximumNumberOfUsers = maxUsers;
        
        for (User u : allUsers) {
            UserWrapper uw = new UserWrapper();
            uw.id = u.Id;
            uw.username = siteName == 'CE_Registry' ? u.CE_Provider_Username__c : u.Username;
            uw.firstName = u.FirstName;
            uw.lastName = u.LastName;
            uw.email = u.Email;
            uw.title = u.Title;
            uw.phone = u.Phone;
            uw.profileId = u.ProfileId;
            uw.profileName = u.Account.Portal_Account_Owner__c == u.Id ? 'CE Registry Owner' : u.Profile.Name;
            uw.isActive = u.IsActive;
            uw.isPortalOwner = u.Account.Portal_Account_Owner__c == u.Id;
            uw.isCurrentUser = u.Id == UserInfo.getUserId();
            uw.ceRegistryAlert = u.CE_Registry_Alert__c;
            
            if (u.IsActive) {
                wrapper.activeUsers.add(uw);
            } else {
                wrapper.inactiveUsers.add(uw);
            }
        }
        
        // Get profiles
        wrapper.profileOptions = getProfileOptions(siteName);
        
        // Get memberships
        // Note: We calculate "current" status in Apex instead of relying on formula field
        // to ensure it works correctly even if formula field has issues
        List<Membership__c> memberships = [
            SELECT Id, Start_Date__c, Expiration_Date__c, Cost__c, Is_Current__c
            FROM Membership__c 
            WHERE Account__c = :userAccountId 
            ORDER BY Expiration_Date__c DESC 
            LIMIT 2
        ];
        
        Date today = Date.today();
        
        if (!memberships.isEmpty()) {
            // Check if first membership is current (Start_Date <= TODAY <= Expiration_Date)
            Membership__c firstMembership = memberships[0];
            Boolean isFirstCurrent = (firstMembership.Start_Date__c != null && 
                                     firstMembership.Expiration_Date__c != null &&
                                     firstMembership.Start_Date__c <= today && 
                                     today <= firstMembership.Expiration_Date__c);
            
            if (isFirstCurrent) {
                wrapper.currentMembership = firstMembership;
            } else if (memberships.size() > 1) {
                // Check if second membership is current
                Membership__c secondMembership = memberships[1];
                Boolean isSecondCurrent = (secondMembership.Start_Date__c != null && 
                                         secondMembership.Expiration_Date__c != null &&
                                         secondMembership.Start_Date__c <= today && 
                                         today <= secondMembership.Expiration_Date__c);
                
                if (isSecondCurrent) {
                    wrapper.currentMembership = secondMembership;
                    // First membership is future (next membership)
                    if (firstMembership.Start_Date__c != null && firstMembership.Start_Date__c > today) {
                        wrapper.nextMembership = firstMembership;
                    }
                } else {
                    // Neither is current, but check if first is future (next membership)
                    if (firstMembership.Start_Date__c != null && firstMembership.Start_Date__c > today) {
                        wrapper.nextMembership = firstMembership;
                    }
                }
            } else {
                // Only one membership, check if it's future (next membership)
                if (firstMembership.Start_Date__c != null && firstMembership.Start_Date__c > today) {
                    wrapper.nextMembership = firstMembership;
                }
            }
        }
        
        // Check if user is CE Provider Administrator for renewal popup
        Boolean isCEProviderAdmin = (currentUser.Profile.Name == 'CE Provider Administrator' || currentUser.Profile.Name == 'CE Administrator');
        
        // Check for renewal popup (14 days or less until expiration)
        // Only show to CE Provider Administrator users
        // Don't show if renewal is complete (nextMembership exists) or expiration is more than a year away
        wrapper.showRenewalPopup = false;
        wrapper.renewalDaysRemaining = null;
        
        if (isCEProviderAdmin && wrapper.currentMembership != null && wrapper.currentMembership.Expiration_Date__c != null) {
            Date expirationDate = wrapper.currentMembership.Expiration_Date__c;
            Integer daysUntilExpiration = Date.today().daysBetween(expirationDate);
            
            // Don't show popup if expiration is more than a year away
            if (daysUntilExpiration > 365) {
                wrapper.showRenewalPopup = false;
                wrapper.renewalDaysRemaining = null;
            }
            // Don't show popup if renewal is complete (any future membership exists)
            else if (wrapper.nextMembership != null) {
                wrapper.showRenewalPopup = false;
                wrapper.renewalDaysRemaining = null;
            }
            // Show popup only if expiration is <= 14 days away and >= 0 (not expired yet)
            // AND no future membership exists (renewal not complete)
            // AND expiration is not more than a year away
            else if (daysUntilExpiration <= 14 && daysUntilExpiration >= 0) {
                wrapper.showRenewalPopup = true;
                wrapper.renewalDaysRemaining = daysUntilExpiration;
            }
        }
        
        // Get content
        wrapper.contentAddUser = getContent('Administration_Add_User__c', siteName);
        wrapper.contentEditUser = getContent('Administration_Edit_User__c', siteName);
        wrapper.contentUpdateAccount = getContent('Administration_Update_Account__c', siteName);
        
        // Get state picklist
        wrapper.statePicklist = getStatePicklist();
        
        // Check if user has feedback access (typically for CE_Registry site)
        // This might need to be adjusted based on your org's permission logic
        wrapper.allowFeedbackAccess = siteName == 'CE_Registry';
        
        return wrapper;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<ProfileOption> getProfileOptions(String siteName) {
        List<ProfileOption> options = new List<ProfileOption>();
        
        if (siteName == null) {
            siteName = 'CE_Registry';
        }
        
        List<String> profileNames = AVAILABLE_PROFILES.get(siteName);
        if (profileNames == null) {
            profileNames = AVAILABLE_PROFILES.get('CE_Registry');
        }
        
        List<Profile> profiles = [SELECT Id, Name FROM Profile WHERE Name IN :profileNames];
        
        for (Profile p : profiles) {
            ProfileOption po = new ProfileOption();
            po.label = p.Name;
            po.value = p.Id;
            options.add(po);
        }
        
        return options;
    }
    
    @AuraEnabled
    public static String saveUser(String userDataJson, Boolean isNewUser, String selectedProfileId) {
        try {
            // Defensive check - ensure userDataJson is not null
            if (String.isBlank(userDataJson)) {
                return 'ERROR: User data is required.';
            }
            
            // Manually deserialize the JSON string to UserWrapper
            // This gives us more control over the deserialization process
            UserWrapper userData = (UserWrapper) JSON.deserialize(userDataJson, UserWrapper.class);
            
            // Debug logging to see what we're receiving
            System.debug('=== saveUser called ===');
            System.debug('userDataJson: ' + userDataJson);
            System.debug('userData: ' + JSON.serialize(userData));
            System.debug('Raw firstName: ' + userData.firstName + ' (null? ' + (userData.firstName == null) + ')');
            System.debug('Raw lastName: ' + userData.lastName + ' (null? ' + (userData.lastName == null) + ')');
            System.debug('Raw username: ' + userData.username + ' (null? ' + (userData.username == null) + ')');
            System.debug('Raw email: ' + userData.email + ' (null? ' + (userData.email == null) + ')');
            System.debug('Raw phone: ' + userData.phone + ' (null? ' + (userData.phone == null) + ')');
            System.debug('isNewUser: ' + isNewUser);
            
            String siteName = Site.getName() != null ? Site.getName() : 'CE_Registry';
            User currentUser = [SELECT AccountId, Contact.RecordTypeId, Account.Owner.UserRoleId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            
            // Normalize string values - handle null/empty strings
            // Apex may deserialize empty strings as null, so we need to handle both cases
            // IMPORTANT: After normalization, all null values become empty strings
            // This ensures validation works correctly after normalization
            if (userData.firstName == null) {
                userData.firstName = '';
            } else {
                userData.firstName = userData.firstName.trim();
            }
            if (userData.lastName == null) {
                userData.lastName = '';
            } else {
                userData.lastName = userData.lastName.trim();
            }
            if (userData.username == null) {
                userData.username = '';
            } else {
                userData.username = userData.username.trim();
            }
            if (userData.email == null) {
                userData.email = '';
            } else {
                userData.email = userData.email.trim();
            }
            if (userData.phone == null) {
                userData.phone = '';
            } else {
                userData.phone = userData.phone.trim();
            }
            if (userData.title == null) {
                userData.title = '';
            } else {
                userData.title = userData.title.trim();
            }
            
            System.debug('After normalization - firstName: [' + userData.firstName + '] (length: ' + userData.firstName.length() + '), lastName: [' + userData.lastName + '] (length: ' + userData.lastName.length() + '), username: [' + userData.username + '], email: [' + userData.email + '], phone: [' + userData.phone + ']');
            
            // Validate
            ValidationResult validation = validateUser(userData, isNewUser, siteName);
            if (!validation.isValid) {
                System.debug('Validation failed: ' + String.join(validation.errors, ', '));
                System.debug('Values at validation time - firstName: [' + userData.firstName + '], lastName: [' + userData.lastName + '], username: [' + userData.username + '], email: [' + userData.email + '], phone: [' + userData.phone + ']');
                // Return detailed error with what we received
                String errorMsg = String.join(validation.errors, ', ');
                String debugInfo = ' (Received: firstName=[' + userData.firstName + '], lastName=[' + userData.lastName + '], username=[' + userData.username + '], email=[' + userData.email + '], phone=[' + userData.phone + '])';
                return 'ERROR: ' + errorMsg + debugInfo;
            }
            
            if (isNewUser) {
                // Create new user via CommunityUtil (if available) or direct creation
                String username = siteName == 'CE_Registry' ? userData.username + CE_USERNAME_SUFFIX : userData.username;
                
                // Check if username already exists
                Integer existingCount = [
                    SELECT COUNT() FROM User 
                    WHERE Username = :username
                ];
                
                if (existingCount > 0) {
                    return 'ERROR: Username is already being used. Please enter a different username.';
                }
                
                // Get Profile ID
                Id profileId;
                if (selectedProfileId != null) {
                    profileId = selectedProfileId;
                } else {
                    // Default to first available profile for the site
                    List<String> profileNames = AVAILABLE_PROFILES.get(siteName);
                    if (profileNames != null && !profileNames.isEmpty()) {
                        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :profileNames[0] AND UserType = 'PowerCustomerSuccess' LIMIT 1];
                        if (!profiles.isEmpty()) {
                            profileId = profiles[0].Id;
                        }
                    }
                }
                
                if (profileId == null) {
                    return 'ERROR: Profile not found. Please select a profile.';
                }
                
                // Get CE_Provider_User RecordType for Contact
                List<RecordType> contactRTList = [
                    SELECT Id 
                    FROM RecordType 
                    WHERE SObjectType = 'Contact' 
                    AND DeveloperName = 'CE_Provider_User' 
                    LIMIT 1
                ];
                
                if (contactRTList.isEmpty()) {
                    return 'ERROR: CE_Provider_User RecordType not found for Contact. Please contact system administrator.';
                }
                
                Id contactRecordTypeId = contactRTList[0].Id;
                
                // Get UserRoleId from Account Owner (if available)
                Id userRoleId = null;
                if (currentUser.Account != null && currentUser.Account.Owner != null) {
                    userRoleId = currentUser.Account.Owner.UserRoleId;
                }
                
                // Create Contact first
                Contact con = new Contact(
                    AccountId = currentUser.AccountId,
                    FirstName = userData.firstName,
                    LastName = userData.lastName,
                    Portal_Username__c = siteName == 'CE_Registry' ? userData.username : null,
                    Email = userData.email,
                    Title = userData.title,
                    Phone = userData.phone,
                    RecordTypeId = contactRecordTypeId,
                    CE_Registry_Alert__c = userData.ceRegistryAlert
                );
                
                Database.insert(con);
                
                // Create User record
                String alias = (userData.firstName != null && userData.firstName.length() >= 2) 
                    ? userData.firstName.substring(0, 2) 
                    : (userData.lastName != null && userData.lastName.length() >= 2) 
                        ? userData.lastName.substring(0, 2) 
                        : 'usr';
                alias += String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 3);
                
                User newUser = new User(
                    FirstName = userData.firstName,
                    LastName = userData.lastName,
                    Username = username,
                    Email = userData.email,
                    Phone = userData.phone,
                    Title = userData.title,
                    Alias = alias,
                    TimeZoneSidKey = 'America/New_York',
                    LocaleSidKey = 'en_US',
                    EmailEncodingKey = 'UTF-8',
                    LanguageLocaleKey = 'en_US',
                    ProfileId = profileId,
                    ContactId = con.Id,
                    IsActive = true,
                    CE_Registry_Alert__c = userData.ceRegistryAlert,
                    UserRoleId = userRoleId
                );
                
                Database.insert(newUser);
                
                return 'SUCCESS';
                
            } else {
                // Update existing user
                User u = [
                    SELECT Id, FirstName, LastName, Email, Title, Phone, ProfileId, CE_Registry_Alert__c, ContactId
                    FROM User WHERE Id = :userData.id LIMIT 1
                ];
                
                u.FirstName = userData.firstName;
                u.LastName = userData.lastName;
                u.Email = userData.email;
                u.Title = userData.title;
                u.Phone = userData.phone;
                u.CE_Registry_Alert__c = userData.ceRegistryAlert;
                
                if (selectedProfileId != null && u.Id != UserInfo.getUserId()) {
                    u.ProfileId = selectedProfileId;
                }
                
                Database.update(u);
                
                // Update Contact
                Contact con = [
                    SELECT Id, FirstName, LastName, Email, Title, Phone, CE_Registry_Alert__c
                    FROM Contact WHERE Id = :u.ContactId LIMIT 1
                ];
                
                con.FirstName = userData.firstName;
                con.LastName = userData.lastName;
                con.Email = userData.email;
                con.Title = userData.title;
                con.Phone = userData.phone;
                con.CE_Registry_Alert__c = userData.ceRegistryAlert;
                
                Database.update(con);
                
                return 'SUCCESS';
            }
        } catch (Exception e) {
            return 'ERROR: ' + e.getMessage();
        }
    }
    
    @AuraEnabled
    public static String inactivateUser(Id userId) {
        try {
            User u = [SELECT Id, IsActive FROM User WHERE Id = :userId LIMIT 1];
            u.IsActive = false;
            Database.update(u);
            return 'SUCCESS';
        } catch (Exception e) {
            return 'ERROR: ' + e.getMessage();
        }
    }
    
    @AuraEnabled
    public static String activateUser(Id userId) {
        try {
            String siteName = Site.getName() != null ? Site.getName() : 'CE_Registry';
            User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            Account acc = [SELECT CE_Max_Portal_users__c, MT_Verify_Max_Portal_Users__c FROM Account WHERE Id = :currentUser.AccountId LIMIT 1];
            
            // Check active user count
            Integer activeCount = [SELECT COUNT() FROM User WHERE AccountId = :currentUser.AccountId AND IsActive = true];
            Integer maxUsers = siteName == 'CE_Registry' ? 
                (acc.CE_Max_Portal_users__c != null ? Integer.valueOf(acc.CE_Max_Portal_users__c) : 3) :
                (acc.MT_Verify_Max_Portal_Users__c != null ? Integer.valueOf(acc.MT_Verify_Max_Portal_Users__c) : 3);
            
            if (activeCount >= maxUsers) {
                return 'ERROR: ' + TOO_MANY_USERS_ERROR;
            }
            
            User u = [SELECT Id, IsActive FROM User WHERE Id = :userId LIMIT 1];
            u.IsActive = true;
            Database.update(u);
            return 'SUCCESS';
        } catch (Exception e) {
            return 'ERROR: ' + e.getMessage();
        }
    }
    
    @AuraEnabled
    public static String removeUser(Id userId) {
        try {
            User u = [SELECT Id, Removed_From_Communities__c FROM User WHERE Id = :userId LIMIT 1];
            u.Removed_From_Communities__c = true;
            Database.update(u);
            return 'SUCCESS';
        } catch (Exception e) {
            return 'ERROR: ' + e.getMessage();
        }
    }
    
    @AuraEnabled
    public static String resetPassword(Id userId) {
        try {
            System.resetPassword(userId, true);
            return 'SUCCESS';
        } catch (Exception e) {
            return 'ERROR: ' + e.getMessage();
        }
    }
    
    @AuraEnabled
    public static String updateAccount(Account account) {
        try {
            // Verify user has access to this account
            User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            if (currentUser.AccountId != account.Id) {
                return 'ERROR: You do not have permission to update this account.';
            }
            
            ValidationResult validation = validateAccount(account);
            if (!validation.isValid) {
                return 'ERROR: ' + String.join(validation.errors, ', ');
            }
            
            // Use AccountUpdateHelper to bypass sharing restrictions for community users
            Database.SaveResult result = AccountUpdateHelper.updateAccount(account);
            if (result.isSuccess()) {
                return 'SUCCESS';
            } else {
                String errorMsg = 'Update failed. ';
                for (Database.Error err : result.getErrors()) {
                    errorMsg += err.getMessage() + ' ';
                }
                return 'ERROR: ' + errorMsg.trim();
            }
        } catch (Exception e) {
            return 'ERROR: ' + e.getMessage();
        }
    }
    
    private static ValidationResult validateUser(UserWrapper userData, Boolean isNewUser, String siteName) {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.errors = new List<String>();
        
        // Defensive check
        if (userData == null) {
            result.isValid = false;
            result.errors.add('User data is required.');
            return result;
        }
        
        // Validate firstName - after normalization, null becomes empty string
        // So we only need to check if it's blank
        if (String.isBlank(userData.firstName)) {
            result.isValid = false;
            result.errors.add('First name is required.');
        }
        
        // Validate lastName - after normalization, null becomes empty string
        if (String.isBlank(userData.lastName)) {
            result.isValid = false;
            result.errors.add('Last name is required.');
        }
        
        // Validate username (only for new users) - after normalization
        if (isNewUser) {
            if (String.isBlank(userData.username)) {
                result.isValid = false;
                result.errors.add('Username is required.');
            } else {
                String username = siteName == 'CE_Registry' ? userData.username + CE_USERNAME_SUFFIX : userData.username;
                Integer existingCount = [SELECT COUNT() FROM User WHERE Username = :username];
                if (existingCount > 0) {
                    result.isValid = false;
                    result.errors.add('Username is already being used. Please enter a different username.');
                }
                
                if (siteName == 'CE_Registry' && userData.username.contains('@')) {
                    result.isValid = false;
                    result.errors.add('Username cannot be formatted as an email address.');
                } else if (siteName == 'Massage_License_Verification_Center' && 
                          (!userData.username.contains('@') || !userData.username.contains('.'))) {
                    result.isValid = false;
                    result.errors.add('Username is not formatted as an email address.');
                }
            }
        }
        
        // Validate email - after normalization
        if (String.isBlank(userData.email)) {
            result.isValid = false;
            result.errors.add('Active email is required and must be formatted as an email address.');
        } else if (!userData.email.contains('@') || !userData.email.contains('.')) {
            result.isValid = false;
            result.errors.add('Active email is required and must be formatted as an email address.');
        }
        
        // Validate phone - after normalization
        if (String.isBlank(userData.phone)) {
            result.isValid = false;
            result.errors.add('Telephone number is required.');
        }
        
        return result;
    }
    
    private static ValidationResult validateAccount(Account account) {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.errors = new List<String>();
        
        if (String.isBlank(account.Email__c) || !account.Email__c.contains('@') || !account.Email__c.contains('.')) {
            result.isValid = false;
            result.errors.add('Active email is required and must be formatted as an email address.');
        }
        
        if (String.isBlank(account.BillingStreet)) {
            result.isValid = false;
            result.errors.add('Address is required.');
        }
        
        if (String.isBlank(account.BillingCity)) {
            result.isValid = false;
            result.errors.add('City is required.');
        }
        
        if (String.isBlank(account.BillingPostalCode)) {
            result.isValid = false;
            result.errors.add('Zip code is required.');
        }
        
        if (String.isBlank(account.Phone)) {
            result.isValid = false;
            result.errors.add('Telephone number is required.');
        }
        
        return result;
    }
    
    private static String getContent(String fieldName, String siteName) {
        try {
            if (siteName == 'CE_Registry') {
                CE_Community_Content__mdt content = [
                    SELECT Administration_Add_User__c, Administration_Edit_User__c, Administration_Update_Account__c
                    FROM CE_Community_Content__mdt
                    WHERE DeveloperName = 'Content' LIMIT 1
                ];
                
                if (fieldName == 'Administration_Add_User__c') {
                    return content.Administration_Add_User__c != null ? content.Administration_Add_User__c : '';
                } else if (fieldName == 'Administration_Edit_User__c') {
                    return content.Administration_Edit_User__c != null ? content.Administration_Edit_User__c : '';
                } else if (fieldName == 'Administration_Update_Account__c') {
                    return content.Administration_Update_Account__c != null ? content.Administration_Update_Account__c : '';
                }
            } else {
                MLVC_Community_Content__mdt content = [
                    SELECT Administration_Add_User__c, Administration_Edit_User__c, Administration_Update_Account__c
                    FROM MLVC_Community_Content__mdt
                    WHERE DeveloperName = 'Content' LIMIT 1
                ];
                
                if (fieldName == 'Administration_Add_User__c') {
                    return content.Administration_Add_User__c != null ? content.Administration_Add_User__c : '';
                } else if (fieldName == 'Administration_Edit_User__c') {
                    return content.Administration_Edit_User__c != null ? content.Administration_Edit_User__c : '';
                } else if (fieldName == 'Administration_Update_Account__c') {
                    return content.Administration_Update_Account__c != null ? content.Administration_Update_Account__c : '';
                }
            }
        } catch (Exception e) {
            return '';
        }
        return '';
    }
    
    private static List<StateOption> getStatePicklist() {
        List<StateOption> options = new List<StateOption>();
        
        // Get state picklist values from Account.BillingStateCode
        Schema.DescribeFieldResult fieldResult = Account.BillingStateCode.getDescribe();
        List<Schema.PicklistEntry> entries = fieldResult.getPicklistValues();
        
        for (Schema.PicklistEntry entry : entries) {
            StateOption so = new StateOption();
            so.label = entry.getLabel();
            so.value = entry.getValue();
            options.add(so);
        }
        
        return options;
    }
    
    // Wrapper classes
    public class AdministrationDataWrapper {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String siteName;
        @AuraEnabled public Account account;
        @AuraEnabled public List<UserWrapper> activeUsers;
        @AuraEnabled public List<UserWrapper> inactiveUsers;
        @AuraEnabled public Integer maximumNumberOfUsers;
        @AuraEnabled public List<ProfileOption> profileOptions;
        @AuraEnabled public Membership__c currentMembership;
        @AuraEnabled public Membership__c nextMembership;
        @AuraEnabled public String contentAddUser;
        @AuraEnabled public String contentEditUser;
        @AuraEnabled public String contentUpdateAccount;
        @AuraEnabled public List<StateOption> statePicklist;
        @AuraEnabled public Boolean allowFeedbackAccess;
        @AuraEnabled public Id contactRecordTypeId;
        @AuraEnabled public Boolean showRenewalPopup;
        @AuraEnabled public Integer renewalDaysRemaining;
    }
    
    public class UserWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String username;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String title;
        @AuraEnabled public String phone;
        @AuraEnabled public Id profileId;
        @AuraEnabled public String profileName;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isPortalOwner;
        @AuraEnabled public Boolean isCurrentUser;
        @AuraEnabled public Boolean ceRegistryAlert;
    }
    
    public class ProfileOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }
    
    public class StateOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }
    
    private class ValidationResult {
        public Boolean isValid;
        public List<String> errors;
    }
}