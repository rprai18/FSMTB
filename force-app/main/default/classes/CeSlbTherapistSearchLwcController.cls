public without sharing class CeSlbTherapistSearchLwcController {
    
    private static final Map<String, String> attributeMap = new Map<String, String> {
        'firstName' => 'FirstName',
        'middleName' => 'Middle_Name__c',
        'lastName' => 'LastName',
        'aka' => 'Previously_Known_As__c'
    };
    
    // Wrapper class for initial data
    public class TherapistSearchDataWrapper {
        @AuraEnabled public List<String> geographicalRegions { get; set; }
        @AuraEnabled public String content { get; set; }
        @AuraEnabled public Boolean showGeographicalRegions { get; set; }
        @AuraEnabled public Boolean hasUserManagementAccess { get; set; }
    }
    
    // Wrapper class for search results
    public class TherapistResult {
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String middleName { get; set; }
        @AuraEnabled public String aka { get; set; }
        @AuraEnabled public String licenseState { get; set; }
        @AuraEnabled public String licenseNumber { get; set; }
        @AuraEnabled public String lastFour { get; set; }
        @AuraEnabled public String url { get; set; }
        @AuraEnabled public Boolean isExamCandidate { get; set; }
        
        // Constructor for therapist with license
        public TherapistResult(Contact contact, State_Licensing__c license) {
            this.contactId = contact.Id;
            this.lastName = contact.LastName;
            this.firstName = contact.FirstName;
            this.middleName = contact.Middle_Name__c;
            this.aka = contact.Previously_Known_As__c;
            this.licenseState = license.Account__r.BillingStateCode;
            this.licenseNumber = license.Number__c;
            this.lastFour = contact.SSN_Last_4_Digits__c;
            this.url = buildUrl(contact.Id);
            this.isExamCandidate = false;
        }
        
        // Constructor for exam candidate (no license)
        public TherapistResult(Contact contact, Boolean examCandidate) {
            this.contactId = contact.Id;
            this.lastName = contact.LastName;
            this.firstName = contact.FirstName;
            this.middleName = contact.Middle_Name__c;
            this.aka = contact.Previously_Known_As__c;
            this.licenseState = null; // Blank for exam candidates
            this.licenseNumber = null; // Blank for exam candidates
            this.lastFour = contact.SSN_Last_4_Digits__c;
            this.url = buildUrl(contact.Id);
            this.isExamCandidate = examCandidate;
        }
        
        private String buildUrl(Id id) {
            // Build URL to SLBTherapistReport page
            String communityUrl = Site.getBaseUrl();
            return communityUrl + '/s/slb-therapist-report?id=' + id;
        }
    }
    
    // Wrapper class for search response
    public class SearchResponseWrapper {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public List<TherapistResult> results { get; set; }
        @AuraEnabled public Integer pageCount { get; set; }
        @AuraEnabled public String message { get; set; }
        
        public SearchResponseWrapper(Boolean success, List<TherapistResult> results, Integer pageCount, String message) {
            this.success = success;
            this.results = results;
            this.pageCount = pageCount;
            this.message = message;
        }
    }
    
    /**
     * Get initial data for the therapist search page
     */
    @AuraEnabled(cacheable=true)
    public static TherapistSearchDataWrapper getTherapistSearchData() {
        TherapistSearchDataWrapper wrapper = new TherapistSearchDataWrapper();
        
        try {
            // Get geographical regions
            Id slbRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'SLB' LIMIT 1].Id;
            wrapper.geographicalRegions = new List<String>();
            
            for (Account acc : [SELECT Id, BillingStateCode FROM Account 
                                WHERE Participating__c = true AND RecordTypeId = :slbRecordTypeId AND BillingStateCode != null
                                ORDER BY BillingStateCode]) {
                wrapper.geographicalRegions.add(acc.BillingStateCode);
            }
            
            // Get content
            try {
                SLB_Community_Content__mdt contentMdt = [SELECT Therapist_Search__c FROM SLB_Community_Content__mdt WHERE DeveloperName = 'Content' LIMIT 1];
                String contentText = contentMdt.Therapist_Search__c;
                if (contentText != null) {
                    wrapper.content = contentText.escapeHtml4().replaceAll('\r\n', '<br />');
                } else {
                    wrapper.content = '';
                }
            } catch (Exception e) {
                wrapper.content = '';
            }
            
            // Get showGeographicalRegions flag
            try {
                User currentUser = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
                if (currentUser.ContactId != null) {
                    Contact c = [SELECT Display_State_Participation_Dialog__c FROM Contact WHERE Id = :currentUser.ContactId LIMIT 1];
                    wrapper.showGeographicalRegions = c.Display_State_Participation_Dialog__c != null ? c.Display_State_Participation_Dialog__c : true;
                } else {
                    wrapper.showGeographicalRegions = true;
                }
            } catch (Exception e) {
                wrapper.showGeographicalRegions = true;
            }
            
            // Get hasUserManagementAccess (similar to other controllers)
            // This would need to be determined based on profile or permission set
            wrapper.hasUserManagementAccess = false; // Default, update based on requirements
            
        } catch (Exception e) {
            System.debug('Error in getTherapistSearchData: ' + e.getMessage());
            throw new AuraHandledException('Error loading therapist search data: ' + e.getMessage());
        }
        
        return wrapper;
    }
    
    /**
     * Search for therapists
     */
    @AuraEnabled
    public static SearchResponseWrapper search(String searchTerm, String lastFourSSN, List<String> stateCodes, 
                                               Integer pageNum, Integer offset, String orderBy, String orderDir) {
        List<TherapistResult> therapistSearchResults = new List<TherapistResult>();
        
        try {
            // Escape inputs
            if (searchTerm != null) {
                searchTerm = String.escapeSingleQuotes(searchTerm);
            }
            if (lastFourSSN != null) {
                lastFourSSN = String.escapeSingleQuotes(lastFourSSN);
            }
            if (stateCodes != null) {
                List<String> escapedStateCodes = new List<String>();
                for (String s : stateCodes) {
                    escapedStateCodes.add(String.escapeSingleQuotes(s));
                }
                stateCodes = escapedStateCodes;
            }
            if (orderDir != null) {
                orderDir = String.escapeSingleQuotes(orderDir);
            }
            
            Set<Id> contactIds = getContactIds(searchTerm, lastFourSSN);
            Set<Id> accountIds = getSelectedAccountIds(stateCodes);
            
            if (contactIds.size() > 0 || accountIds.size() > 0) {
                Id therapistRecordTypeId;
                try {
                    therapistRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Contact' AND DeveloperName = 'TherapistRecord' LIMIT 1].Id;
                } catch (Exception e) {
                    System.debug('Error getting TherapistRecord RecordType: ' + e.getMessage());
                    return new SearchResponseWrapper(false, new List<TherapistResult>(), 0, 'Error: Therapist RecordType not found. Please contact your administrator.');
                }
                
                String query = 'SELECT FirstName, Middle_Name__c, LastName, Previously_Known_As__c, SSN_Last_4_Digits__c, ';
                
                // Include State Licensing records
                if (accountIds.size() > 0) {
                    query += '(SELECT Number__c, Account__r.BillingStateCode FROM StatesLicensing__r WHERE Account__c IN :accountIds), ';
                } else {
                    query += '(SELECT Number__c, Account__r.BillingStateCode FROM StatesLicensing__r), ';
                }
                
                // Include Exam records for exam candidates
                query += '(SELECT Id, Source__c FROM Exams__r WHERE Source__c = \'FSMTB\') ';
                
                query += 'FROM Contact WHERE RecordTypeId = :therapistRecordTypeId ';
                
                if (contactIds.size() > 0) {
                    query += 'AND Id IN :contactIds ';
                }
                
                if (accountIds.size() > 0) {
                    query += 'AND Id IN (SELECT Contact__c FROM State_Licensing__c WHERE Account__c IN :accountIds) ';
                }
                
                if (orderBy != null && !orderBy.equals('')) {
                    String orderByField = attributeMap.get(orderBy);
                    if (orderByField != null) {
                        query += 'ORDER BY ' + orderByField + ' ';
                        query += orderDir != null && !orderDir.equals('') ? orderDir + ' NULLS LAST ' : ' ASC NULLS LAST ';
                    } else {
                        query += 'ORDER BY LastName NULLS LAST ';
                    }
                } else {
                    query += 'ORDER BY LastName NULLS LAST ';
                }
                
                Integer limitValue = offset != null && offset != 0 ? offset : 1000; // Get more results for client-side pagination
                Integer offsetValue = pageNum != null && pageNum != 0 ? pageNum * limitValue : 0;
                query += 'LIMIT ' + limitValue + ' OFFSET ' + offsetValue;
                
                List<Contact> therapists = Database.query(query);
                
                for (Contact contact : therapists) {
                    if (contact.StatesLicensing__r != null && contact.StatesLicensing__r.size() > 0) {
                        // Therapist with licenses - create a result for each license
                        for (State_Licensing__c license : contact.StatesLicensing__r) {
                            therapistSearchResults.add(new TherapistResult(contact, license));
                        }
                    } else if (contact.Exams__r != null && contact.Exams__r.size() > 0) {
                        // Exam candidate - has FSMTB exam but no State Licensing records
                        // Only show if they have exam records (visual indicator distinguishes them)
                        therapistSearchResults.add(new TherapistResult(contact, true));
                    }
                }
            }
            
            Integer pageCount = getPageCount(contactIds, accountIds, offset);
            
            return new SearchResponseWrapper(true, therapistSearchResults, pageCount, null);
            
        } catch (Exception e) {
            System.debug('Error in search: ' + e.getMessage());
            return new SearchResponseWrapper(false, new List<TherapistResult>(), 0, 'Error performing search: ' + e.getMessage());
        }
    }
    
    /**
     * Set showGeographicalRegions flag
     */
    @AuraEnabled
    public static Boolean setShowParticipating(Boolean bool) {
        try {
            Id contactId = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].ContactId;
            
            if (contactId != null) {
                Contact c = new Contact(
                    Id = contactId,
                    Display_State_Participation_Dialog__c = bool
                );
                
                Database.SaveResult result = Database.update(c);
                return result.isSuccess();
            }
            
            return false;
        } catch (Exception e) {
            System.debug('Error in setShowParticipating: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * Get participating account IDs
     */
    private static Map<String, Id> getParticipatingAccounts() {
        Map<String, Id> participatingAccounts = new Map<String, Id>();
        
        Id slbRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'SLB' LIMIT 1].Id;
        
        for (Account acc : [SELECT Id, BillingStateCode FROM Account 
                            WHERE Participating__c = true AND RecordTypeId = :slbRecordTypeId AND BillingStateCode != null
                            ORDER BY BillingStateCode]) {
            participatingAccounts.put(acc.BillingStateCode, acc.Id);
        }
        
        return participatingAccounts;
    }
    
    /**
     * Get selected account IDs from state codes
     */
    private static Set<Id> getSelectedAccountIds(List<String> territories) {
        Set<Id> accountIds = new Set<Id>();
        Map<String, Id> participatingAccounts = getParticipatingAccounts();
        
        if (territories != null) {
            for (String territory : territories) {
                Id accountId = participatingAccounts.get(territory);
                if (accountId != null) {
                    accountIds.add(accountId);
                }
            }
        }
        
        return accountIds;
    }
    
    /**
     * Get contact IDs from search term and SSN
     */
    private static Set<Id> getContactIds(String searchTerm, String lastFourSSN) {
        String findClause = buildFindClause(searchTerm != null ? String.escapeSingleQuotes(searchTerm) : '');
        Set<Id> contactIds = new Set<Id>();
        
        if (searchTerm != null && searchTerm.length() > 0) {
            // Search both State_Licensing__c (for license numbers) and Contact (for names)
            List<List<SObject>> keywordResults = [
                FIND :findClause IN ALL FIELDS RETURNING
                    State_Licensing__c (Contact__c),
                    Contact (Id)
            ];
            
            // Results from State_Licensing__c (license-based search)
            for (SObject record : keywordResults.get(0)) {
                contactIds.add(((State_Licensing__c) record).Contact__c);
            }
            
            // Results from Contact (name-based search)
            for (SObject record : keywordResults.get(1)) {
                contactIds.add(((Contact) record).Id);
            }
        }
        
        if (lastFourSSN != null && lastFourSSN.length() > 0) {
            // Direct SOQL on last 4 field, but filter by Therapist RecordType to ensure consistency
            Id therapistRecordTypeId;
            try {
                therapistRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Contact' AND DeveloperName = 'TherapistRecord' LIMIT 1].Id;
            } catch (Exception e) {
                // If record type not found, return empty set
                return contactIds;
            }
            
            // Query contacts with SSN and correct RecordType
            for (Contact c : [
                SELECT Id
                FROM Contact
                WHERE SSN_Last_4_Digits__c = :lastFourSSN
                AND RecordTypeId = :therapistRecordTypeId
            ]) {
                contactIds.add(c.Id);
            }
        }
        
        return contactIds;
    }
    
    /**
     * Build FIND clause from search term
     */
    private static String buildFindClause(String input) {
        if (input == null || input.length() == 0) {
            return '\'\'';
        }
        
        // If user included explicit wildcards, pass input through as-is.
        if (input.contains('*') || input.contains('?')) {
            return '\'' + input + '\'';
        }
        
        // Otherwise, treat each token as a prefix term and append * so
        // 'Doc' will match 'Doctor', 'Document', etc.
        List<String> tokens = input.split(' ');
        String findClause = '\'';
        for (Integer i = 0; i < tokens.size(); i++) {
            String token = tokens[i];
            if (String.isBlank(token)) {
                continue;
            }
            findClause += token + '*';
            if (i != tokens.size() - 1) {
                findClause += ' AND ';
            }
        }
        return findClause + '\'';
    }
    
    /**
     * Get page count for pagination
     */
    private static Integer getPageCount(Set<Id> contactIds, Set<Id> accountIds, Integer offset) {
        Id therapistRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Contact' AND DeveloperName = 'TherapistRecord' LIMIT 1].Id;
        
        String q = 'SELECT COUNT() FROM Contact WHERE RecordTypeId = :therapistRecordTypeId ';
        
        if (contactIds.size() > 0) {
            q += 'AND Id IN :contactIds ';
        }
        
        if (accountIds.size() > 0) {
            q += 'AND Id IN (SELECT Contact__c FROM State_Licensing__c WHERE Account__c IN :accountIds) ';
        }
        
        Integer totalCount = Database.countQuery(q);
        Integer offsetValue = offset != null && offset != 0 ? offset : 25;
        return totalCount > 0 ? Integer.valueOf(Math.ceil(Decimal.valueOf(totalCount) / Decimal.valueOf(offsetValue))) : 0;
    }
}

