public with sharing class MyRosterUploadHandler {
    private static final Set<String> VALID_STATE_CODES = new Set<String>{
        'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'DC', 'FL', 'GA', 'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY',
        'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH',
        'OK', 'OR', 'PA', 'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY', 'AS', 'GU', 'MP',
        'PR', 'VI'
    };
    
    /**
     * Helper method to get the first active picklist value for File_Processed__c
     * Used when marking a file as processed
     */
    private static String getFileProcessedValue() {
        try {
            Schema.DescribeFieldResult fieldResult = Roster_Upload__c.File_Processed__c.getDescribe();
            List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
            
            // Find the first active value (typically "Yes", "Processed", "True", etc.)
            for (Schema.PicklistEntry entry : picklistValues) {
                if (entry.isActive()) {
                    return entry.getValue();
                }
            }
        } catch (Exception e) {
            System.debug('Error getting File_Processed__c picklist values: ' + e.getMessage());
        }
        return null;
    }
    
    /**
     * Helper method to get a valid picklist value for File_Processed__c that represents "not processed"
     * Looks for values like "No", "Not Processed", "False", etc., or returns the first value if not found
     */
    private static String getFileNotProcessedValue() {
        try {
            Schema.DescribeFieldResult fieldResult = Roster_Upload__c.File_Processed__c.getDescribe();
            List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
            
            // Look for common "not processed" values first
            List<String> notProcessedValues = new List<String>{'No', 'Not Processed', 'False', 'Incomplete', 'Pending'};
            for (Schema.PicklistEntry entry : picklistValues) {
                if (entry.isActive() && notProcessedValues.contains(entry.getValue())) {
                    return entry.getValue();
                }
            }
            
            // If no "not processed" value found, return the first active value
            for (Schema.PicklistEntry entry : picklistValues) {
                if (entry.isActive()) {
                    return entry.getValue();
                }
            }
        } catch (Exception e) {
            System.debug('Error getting File_Processed__c picklist values: ' + e.getMessage());
        }
        return null;
    }
    
    // Wrapper class for session options
    public class SessionOption {
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String sessionId { get; set; }
        @AuraEnabled public String instructorName { get; set; }
        @AuraEnabled public String recordType { get; set; }
        @AuraEnabled public Date lastTimeFrameEndDate { get; set; }
    }
    
    // Get sessions for a course
    @AuraEnabled(cacheable=true)
    public static List<SessionOption> getSessions(Id courseId) {
        List<SessionOption> options = new List<SessionOption>();
        
        if (courseId == null) {
            return options;
        }
        
        try {
            // Get On Demand record type ID
            Id onDemandRecordTypeId;
            try {
                onDemandRecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'On_Demand' LIMIT 1].Id;
            } catch (Exception e) {
                System.debug('On_Demand record type not found');
            }
            
            // Query sessions matching VF controller logic exactly:
            // (Status_Selected__c = 'Complete' AND Course__c = :courseId AND End_Date__c <= TODAY)
            // OR (Course__c = :courseId AND RecordTypeId = :onDemandRecordTypeId AND Status_Selected__c NOT IN ('Denied', 'Draft'))
            List<Session__c> sessions = [
                SELECT Id, Name, Instructor_Name__c, Session_Type__c, End_Date__c, RecordTypeId, Last_Time_Frame_End_Date__c
                FROM Session__c
                WHERE (Status_Selected__c = 'Complete' AND Course__c = :courseId AND End_Date__c <= TODAY)
                OR (Course__c = :courseId AND RecordTypeId = :onDemandRecordTypeId AND Status_Selected__c NOT IN ('Denied', 'Draft'))
                ORDER BY Name ASC
            ];
            
            for (Session__c session : sessions) {
                SessionOption option = new SessionOption();
                option.value = session.Id;
                
                // Build label: Session ID - Instructor Name - Session Type
                // Format base: SESID-0000167 - Nina Patterson - Live - On Site
                List<String> labelParts = new List<String>();
                if (String.isNotBlank(session.Name)) {
                    labelParts.add(session.Name);
                }
                if (String.isNotBlank(session.Instructor_Name__c)) {
                    labelParts.add(session.Instructor_Name__c);
                }
                if (String.isNotBlank(session.Session_Type__c)) {
                    labelParts.add(session.Session_Type__c);
                }
                
                // Add End Date only if NOT On Demand and Last_Time_Frame_End_Date__c has a value
                // Format: End Date: 12/6/25 (MM/DD/YY, no zero padding)
                Boolean isOnDemand = (session.RecordTypeId == onDemandRecordTypeId);
                if (!isOnDemand && session.Last_Time_Frame_End_Date__c != null) {
                    Datetime dt = session.Last_Time_Frame_End_Date__c;
                    Date endDate = dt.date();
                    // Format as M/D/YY (no zero padding, matching example: 12/6/25)
                    Integer monthInt = endDate.month();
                    Integer dayInt = endDate.day();
                    String year = String.valueOf(endDate.year()).substring(2); // Last 2 digits
                    labelParts.add('End Date: ' + monthInt + '/' + dayInt + '/' + year);
                }
                
                option.label = String.join(labelParts, ' - ');
                option.sessionId = session.Name;
                option.instructorName = session.Instructor_Name__c;
                option.recordType = isOnDemand ? 'On_Demand' : '';
                // Convert Last_Time_Frame_End_Date__c from Datetime to Date
                if (session.Last_Time_Frame_End_Date__c != null) {
                    Datetime dt = session.Last_Time_Frame_End_Date__c;
                    option.lastTimeFrameEndDate = dt.date();
                }
                
                options.add(option);
            }
        } catch (Exception e) {
            System.debug('Error in getSessions: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving sessions: ' + e.getMessage());
        }
        
        return options;
    }
    
    // Get courses for the current user's account
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCourses() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        
        try {
            // Get account ID - try both User.AccountId and User.Contact.AccountId for community users
            User currentUser = [SELECT AccountId, Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            Id accountId = currentUser.Contact?.AccountId != null ? currentUser.Contact.AccountId : currentUser.AccountId;
            
            System.debug('getCourses - Current User AccountId: ' + accountId);
            System.debug('getCourses - User.AccountId: ' + currentUser.AccountId);
            System.debug('getCourses - User.Contact.AccountId: ' + currentUser.Contact?.AccountId);
            
            if (accountId == null) {
                System.debug('getCourses - AccountId is null, returning empty list');
                return options;
            }
            
            // Query all courses for the account - try both Account__c and Contact__r.AccountId
            // to ensure we find all courses
            List<Course__c> courses = new List<Course__c>();
            
            // First try Account__c field (direct account relationship)
            List<Course__c> coursesByAccount = [
                SELECT Id, Course_Name__c, Name, Account__c, Contact__r.AccountId
                FROM Course__c
                WHERE Account__c = :accountId
                ORDER BY Name ASC
            ];
            System.debug('getCourses - Found ' + coursesByAccount.size() + ' courses by Account__c');
            
            // Then try Contact__r.AccountId
            List<Course__c> coursesByContactAccount = [
                SELECT Id, Course_Name__c, Name, Account__c, Contact__r.AccountId
                FROM Course__c
                WHERE Contact__r.AccountId = :accountId
                ORDER BY Name ASC
            ];
            System.debug('getCourses - Found ' + coursesByContactAccount.size() + ' courses by Contact__r.AccountId');
            
            // Combine and deduplicate
            Map<Id, Course__c> courseMap = new Map<Id, Course__c>();
            for (Course__c c : coursesByAccount) {
                courseMap.put(c.Id, c);
            }
            for (Course__c c : coursesByContactAccount) {
                courseMap.put(c.Id, c);
            }
            courses = courseMap.values();
            
            System.debug('getCourses - Total unique courses found: ' + courses.size());
            
            for (Course__c course : courses) {
                Map<String, String> option = new Map<String, String>();
                option.put('value', course.Id);
                option.put('label', course.Name + ' - ' + course.Course_Name__c);
                options.add(option);
            }
            
            System.debug('getCourses - Returning ' + options.size() + ' course options');
        } catch (Exception e) {
            System.debug('Error in getCourses: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving courses: ' + e.getMessage());
        }
        
        return options;
    }
    
    // Get roster uploads for the current user
    @AuraEnabled(cacheable=true)
    public static List<Roster_Upload__c> getRosters() {
        try {
            // Match VF controller: accountId = [SELECT Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId()][0].Contact.AccountId;
            User currentUser = [SELECT Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            Id accountId = currentUser.Contact.AccountId;
            
            System.debug('getRosters - accountId: ' + accountId);
            
            if (accountId == null) {
                System.debug('getRosters - accountId is null, returning empty list');
                return new List<Roster_Upload__c>();
            }
            
            // Get On Demand record type ID for filtering (matching VF controller populateRosterList)
            Id onDemandRecordTypeId;
            try {
                onDemandRecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'On_Demand' LIMIT 1].Id;
                System.debug('getRosters - onDemandRecordTypeId: ' + onDemandRecordTypeId);
            } catch (Exception e) {
                System.debug('On_Demand record type not found');
            }
            
            // Query all rosters for the account, regardless of session status
            // This ensures newly created rosters appear in the table immediately
            // The VF controller filters by session status, but we'll show all rosters here
            // to ensure newly created ones are visible
            List<Roster_Upload__c> rosters = [
                SELECT Id, Upload_Date__c, File_Processed__c, Session_Completion_Date__c,
                       Session__r.Course__r.Course_Name__c,
                       Session__r.Course__r.Name,
                       Session__r.Name,
                       Number_of_Records__c, Successful_Records__c, Uploaded_By__c,
                       Session__r.Status_Selected__c, Session__r.RecordTypeId
                FROM Roster_Upload__c
                WHERE Session__r.Course__r.Contact__r.AccountId = :accountId
                ORDER BY Upload_Date__c DESC
                LIMIT 100
            ];
            
            System.debug('getRosters - Query returned ' + rosters.size() + ' rosters for accountId: ' + accountId);
            return rosters;
        } catch (Exception e) {
            System.debug('Error in getRosters: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving rosters: ' + e.getMessage());
        }
    }
    
    // Get content for the roster upload page
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getContent() {
        Map<String, String> content = new Map<String, String>();
        
        try {
            // Query Custom Metadata for Roster Upload content
            // The record DeveloperName is "Content" and it has a field Roster_Upload__c
            List<CE_Community_Content__mdt> rosterContents = [
                SELECT Roster_Upload__c 
                FROM CE_Community_Content__mdt 
                WHERE DeveloperName = 'Content' 
                LIMIT 1
            ];
            
            String instructionalHtml = '';
            if (!rosterContents.isEmpty() && String.isNotBlank(rosterContents[0].Roster_Upload__c)) {
                instructionalHtml = rosterContents[0].Roster_Upload__c;
            } else {
                // Fallback to default content if metadata not found
                instructionalHtml = '<p>Rosters can only be uploaded for courses and sessions that have been registered with CE Registry and completed. If you have any questions regarding uploading files, please contact FSMTB at <a href="mailto:CE@fsmtb.org">CE@fsmtb.org</a>.</p>' +
                    '<p>The records below show your attempted roster uploads, including the number of records you attempted to upload and how many of those were successful. The administrative users and owners are notified about unsuccessful uploads.</p>';
            }
            
            content.put('content', instructionalHtml);
            content.put('contentUploadMessage', '');
            content.put('contentSelectFile', '');
            content.put('contentSuccess', '');
        } catch (Exception e) {
            System.debug('Error in getContent: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // Return default content on error
            content.put('content', '<p>Rosters can only be uploaded for courses and sessions that have been registered with CE Registry and completed. If you have any questions regarding uploading files, please contact FSMTB at <a href="mailto:CE@fsmtb.org">CE@fsmtb.org</a>.</p><p>The records below show your attempted roster uploads, including the number of records you attempted to upload and how many of those were successful. The administrative users and owners are notified about unsuccessful uploads.</p>');
            content.put('contentUploadMessage', '');
            content.put('contentSelectFile', '');
            content.put('contentSuccess', '');
        }
        
        return content;
    }
    
    // Get course and session names for display (without creating Roster_Upload__c record)
    @AuraEnabled
    public static Map<String, Object> getCourseSessionInfo(Id courseId, Id sessionId) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // Get course and session names
            Course__c course = [SELECT Course_Name__c, Name FROM Course__c WHERE Id = :courseId LIMIT 1];
            Session__c session = [SELECT Name FROM Session__c WHERE Id = :sessionId LIMIT 1];
            
            result.put('courseName', course.Course_Name__c);
            result.put('sessionName', session.Name);
            result.put('success', 'true');
        } catch (Exception e) {
            System.debug('Error in getCourseSessionInfo: ' + e.getMessage());
            result.put('success', 'false');
            result.put('error', e.getMessage());
            throw new AuraHandledException('Error getting course/session info: ' + e.getMessage());
        }
        
        return result;
    }
    
    // Start upload process - create Roster_Upload__c record
    // NOTE: This method is kept for backward compatibility but Roster_Upload__c is now created in uploadRosterFile
    @AuraEnabled
    public static Map<String, Object> startUpload(Id courseId, Id sessionId) {
        // Just return course/session info without creating the record
        return getCourseSessionInfo(courseId, sessionId);
    }
    
    // Wrapper class for roster entry validation and display
    public class RosterEntry {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String stateOfLicense1;
        @AuraEnabled public String licenseNumber1;
        @AuraEnabled public String stateOfLicense2;
        @AuraEnabled public String licenseNumber2;
        @AuraEnabled public String stateOfLicense3;
        @AuraEnabled public String licenseNumber3;
        @AuraEnabled public String email;
        @AuraEnabled public String courseCompletedOn;
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public String errorMessage;
        
        public RosterEntry(Integer rowNum) {
            this.rowNumber = rowNum;
            this.isValid = true;
            this.errorMessage = '';
        }
    }
    
    // Validate and parse roster data (CSV or manual entry)
    @AuraEnabled
    public static Map<String, Object> validateRosterData(String base64Data, List<Map<String, String>> manualEntries) {
        Map<String, Object> result = new Map<String, Object>();
        List<RosterEntry> entries = new List<RosterEntry>();
        Boolean hasErrors = false;
        Integer validCount = 0;
        Integer invalidCount = 0;
        
        try {
            List<List<String>> rows = new List<List<String>>();
            
            // If manual entries provided, use those; otherwise parse CSV
            if (manualEntries != null && !manualEntries.isEmpty()) {
                for (Map<String, String> entry : manualEntries) {
                    List<String> row = new List<String>();
                    row.add(entry.get('firstName') != null ? entry.get('firstName') : '');
                    row.add(entry.get('lastName') != null ? entry.get('lastName') : '');
                    row.add(entry.get('stateOfLicense1') != null ? entry.get('stateOfLicense1') : '');
                    row.add(entry.get('licenseNumber1') != null ? entry.get('licenseNumber1') : '');
                    row.add(entry.get('stateOfLicense2') != null ? entry.get('stateOfLicense2') : '');
                    row.add(entry.get('licenseNumber2') != null ? entry.get('licenseNumber2') : '');
                    row.add(entry.get('stateOfLicense3') != null ? entry.get('stateOfLicense3') : '');
                    row.add(entry.get('licenseNumber3') != null ? entry.get('licenseNumber3') : '');
                    row.add(entry.get('email') != null ? entry.get('email') : '');
                    row.add(entry.get('courseCompletedOn') != null ? entry.get('courseCompletedOn') : '');
                    rows.add(row);
                }
            } else if (String.isNotBlank(base64Data)) {
                // Parse CSV from base64
                String csvContent = EncodingUtil.base64Decode(base64Data).toString();
                rows = parseCSV(csvContent);
            }
            
            // Detect header row and determine column positions dynamically
            Integer startIndex = 0;
            Map<String, Integer> columnMap = new Map<String, Integer>(); // Map field names to column indices
            Boolean hasHeader = false;
            
            if (rows.size() > 0) {
                List<String> firstRow = rows[0];
                // Check if first row looks like a header by checking for common header keywords
                Boolean looksLikeHeader = false;
                if (firstRow.size() > 0) {
                    String firstCell = firstRow[0] != null ? firstRow[0].trim().toLowerCase() : '';
                    looksLikeHeader = firstCell.contains('first') || 
                                     firstCell.contains('name') ||
                                     firstCell.equals('firstname') ||
                                     firstCell.equals('first name');
                }
                
                if (looksLikeHeader) {
                    hasHeader = true;
                    startIndex = 1;
                    
                    // Parse header row to find column positions dynamically
                    for (Integer colIdx = 0; colIdx < firstRow.size(); colIdx++) {
                        String headerCell = firstRow[colIdx] != null ? firstRow[colIdx].trim().toLowerCase() : '';
                        headerCell = headerCell.replace(' ', '').replace('_', '').replace('#', '');
                        
                        // Map header names to field names (flexible matching)
                        if (headerCell.contains('firstname') || headerCell.equals('first')) {
                            columnMap.put('firstName', colIdx);
                        } else if (headerCell.contains('lastname') || headerCell.equals('last')) {
                            columnMap.put('lastName', colIdx);
                        } else if (headerCell.contains('stateoflicense') || 
                                  (headerCell.contains('state') && headerCell.contains('license'))) {
                            if (headerCell.contains('3')) {
                                columnMap.put('stateOfLicense3', colIdx);
                            } else if (headerCell.contains('2')) {
                                columnMap.put('stateOfLicense2', colIdx);
                            } else {
                                columnMap.put('stateOfLicense1', colIdx);
                            }
                        } else if (headerCell.contains('licensenumber') || 
                                  (headerCell.contains('license') && headerCell.contains('number'))) {
                            if (headerCell.contains('3')) {
                                columnMap.put('licenseNumber3', colIdx);
                            } else if (headerCell.contains('2')) {
                                columnMap.put('licenseNumber2', colIdx);
                            } else {
                                columnMap.put('licenseNumber1', colIdx);
                            }
                        } else if (headerCell.contains('email')) {
                            columnMap.put('email', colIdx);
                        } else if (headerCell.contains('coursecompleted') || 
                                  (headerCell.contains('course') && headerCell.contains('completed'))) {
                            columnMap.put('courseCompletedOn', colIdx);
                        }
                    }
                }
            }
            
            // If no header found or column map incomplete, fall back to position-based detection
            Boolean usePositionBased = columnMap.isEmpty() || 
                                      !columnMap.containsKey('email') || 
                                      !columnMap.containsKey('courseCompletedOn');
            
            if (usePositionBased) {
                // Fall back to position-based: detect format by column count
                Boolean isExtendedFormat = false;
                if (rows.size() > startIndex) {
                    List<String> firstDataRow = rows[startIndex];
                    if (firstDataRow.size() >= 10) {
                        isExtendedFormat = true;
                    }
                }
                
                // Set default column positions based on format
                columnMap.put('firstName', 0);
                columnMap.put('lastName', 1);
                columnMap.put('stateOfLicense1', 2);
                columnMap.put('licenseNumber1', 3);
                if (isExtendedFormat) {
                    columnMap.put('stateOfLicense2', 4);
                    columnMap.put('licenseNumber2', 5);
                    columnMap.put('stateOfLicense3', 6);
                    columnMap.put('licenseNumber3', 7);
                    columnMap.put('email', 8);
                    columnMap.put('courseCompletedOn', 9);
                } else {
                    columnMap.put('email', 4);
                    columnMap.put('courseCompletedOn', 5);
                }
            }
            
            // Validate each row
            for (Integer i = startIndex; i < rows.size(); i++) {
                List<String> row = rows[i];
                
                // Skip empty rows
                Boolean isEmpty = true;
                for (String cell : row) {
                    if (String.isNotBlank(cell)) {
                        isEmpty = false;
                        break;
                    }
                }
                if (isEmpty) continue;
                
                RosterEntry entry = new RosterEntry(i - startIndex + 1);
                
                // Extract fields using column map (dynamic) or fallback to position-based
                Integer firstNameIdx = columnMap.get('firstName');
                Integer lastNameIdx = columnMap.get('lastName');
                Integer stateIdx = columnMap.get('stateOfLicense1');
                Integer licenseIdx = columnMap.get('licenseNumber1');
                Integer state2Idx = columnMap.get('stateOfLicense2');
                Integer license2Idx = columnMap.get('licenseNumber2');
                Integer state3Idx = columnMap.get('stateOfLicense3');
                Integer license3Idx = columnMap.get('licenseNumber3');
                Integer emailIdx = columnMap.get('email');
                Integer dateIdx = columnMap.get('courseCompletedOn');
                
                if (firstNameIdx != null && row.size() > firstNameIdx) {
                    entry.firstName = row[firstNameIdx] != null ? row[firstNameIdx].trim() : '';
                }
                if (lastNameIdx != null && row.size() > lastNameIdx) {
                    entry.lastName = row[lastNameIdx] != null ? row[lastNameIdx].trim() : '';
                }
                if (stateIdx != null && row.size() > stateIdx) {
                    entry.stateOfLicense1 = row[stateIdx] != null ? row[stateIdx].trim().toUpperCase() : '';
                }
                if (licenseIdx != null && row.size() > licenseIdx) {
                    entry.licenseNumber1 = row[licenseIdx] != null ? row[licenseIdx].trim() : '';
                }
                if (state2Idx != null && row.size() > state2Idx) {
                    entry.stateOfLicense2 = row[state2Idx] != null ? row[state2Idx].trim().toUpperCase() : '';
                }
                if (license2Idx != null && row.size() > license2Idx) {
                    entry.licenseNumber2 = row[license2Idx] != null ? row[license2Idx].trim() : '';
                }
                if (state3Idx != null && row.size() > state3Idx) {
                    entry.stateOfLicense3 = row[state3Idx] != null ? row[state3Idx].trim().toUpperCase() : '';
                }
                if (license3Idx != null && row.size() > license3Idx) {
                    entry.licenseNumber3 = row[license3Idx] != null ? row[license3Idx].trim() : '';
                }
                if (emailIdx != null && row.size() > emailIdx) {
                    entry.email = row[emailIdx] != null ? row[emailIdx].trim() : '';
                }
                if (dateIdx != null && row.size() > dateIdx) {
                    entry.courseCompletedOn = row[dateIdx] != null ? row[dateIdx].trim() : '';
                }
                
                // Validate entry
                List<String> errors = validateRosterEntry(entry);
                if (!errors.isEmpty()) {
                    entry.isValid = false;
                    entry.errorMessage = String.join(errors, '; ');
                    invalidCount++;
                    hasErrors = true;
                } else {
                    validCount++;
                }
                
                entries.add(entry);
            }
            
            result.put('entries', entries);
            result.put('hasErrors', hasErrors);
            result.put('validCount', validCount);
            result.put('invalidCount', invalidCount);
            result.put('totalCount', entries.size());
            result.put('success', 'true');
            
        } catch (Exception e) {
            System.debug('Error in validateRosterData: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            result.put('success', 'false');
            result.put('message', 'Error validating roster data: ' + e.getMessage());
        }
        
        return result;
    }
    
    // Helper method to parse CSV
    private static List<List<String>> parseCSV(String csvContent) {
        List<List<String>> rows = new List<List<String>>();
        
        if (String.isBlank(csvContent)) {
            return rows;
        }
        
        // Split by lines
        List<String> lines = csvContent.split('\n');
        
        for (String line : lines) {
            if (String.isBlank(line)) continue;
            
            List<String> row = new List<String>();
            Boolean inQuotes = false;
            String currentField = '';
            
            for (Integer i = 0; i < line.length(); i++) {
                String currentChar = line.substring(i, i + 1);
                
                if (currentChar == '"') {
                    inQuotes = !inQuotes;
                } else if (currentChar == ',' && !inQuotes) {
                    row.add(currentField);
                    currentField = '';
                } else {
                    currentField += currentChar;
                }
            }
            
            // Add the last field
            row.add(currentField);
            rows.add(row);
        }
        
        return rows;
    }
    
    // Validate a single roster entry
    private static List<String> validateRosterEntry(RosterEntry entry) {
        List<String> errors = new List<String>();
        
        // First Name (required)
        if (String.isBlank(entry.firstName)) {
            errors.add('First Name is required');
        }
        
        // Last Name (required)
        if (String.isBlank(entry.lastName)) {
            errors.add('Last Name is required');
        }
        
        // State of License #1 (required, 2-letter code)
        if (String.isBlank(entry.stateOfLicense1)) {
            errors.add('State of License #1 is required');
        } else if (!VALID_STATE_CODES.contains(entry.stateOfLicense1.toUpperCase())) {
            errors.add('State of License #1 must be a valid state/territory');
        }
        
        // License Number #1 (required)
        if (String.isBlank(entry.licenseNumber1)) {
            errors.add('License Number #1 is required');
        }

        // State/License #2 optional, but both must be provided together and state must be valid.
        Boolean hasState2 = String.isNotBlank(entry.stateOfLicense2);
        Boolean hasLicense2 = String.isNotBlank(entry.licenseNumber2);
        if (hasState2 || hasLicense2) {
            if (!hasState2) {
                errors.add('State of License #2 is required when License Number #2 is provided');
            } else if (!VALID_STATE_CODES.contains(entry.stateOfLicense2.toUpperCase())) {
                errors.add('State of License #2 must be a valid state/territory');
            }
            if (!hasLicense2) {
                errors.add('License Number #2 is required when State of License #2 is provided');
            }
        }

        // State/License #3 optional, but both must be provided together and state must be valid.
        Boolean hasState3 = String.isNotBlank(entry.stateOfLicense3);
        Boolean hasLicense3 = String.isNotBlank(entry.licenseNumber3);
        if (hasState3 || hasLicense3) {
            if (!hasState3) {
                errors.add('State of License #3 is required when License Number #3 is provided');
            } else if (!VALID_STATE_CODES.contains(entry.stateOfLicense3.toUpperCase())) {
                errors.add('State of License #3 must be a valid state/territory');
            }
            if (!hasLicense3) {
                errors.add('License Number #3 is required when State of License #3 is provided');
            }
        }
        
        // Email (required, valid format)
        if (String.isBlank(entry.email)) {
            errors.add('Email is required');
        } else {
            String emailRegex = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
            Pattern emailPattern = Pattern.compile(emailRegex);
            if (!emailPattern.matcher(entry.email).matches()) {
                errors.add('Email must be in valid format');
            }
        }
        
        // Course Completed On (required; accepts MM/DD/YYYY, M/D/YY, M/D/YYYY, Excel serial)
        if (String.isBlank(entry.courseCompletedOn)) {
            errors.add('Course Completed On is required');
        } else {
            String normalizedDate = normalizeCourseCompletedDate(entry.courseCompletedOn);
            if (normalizedDate == null) {
                errors.add('Course Completed On must be in MM/DD/YYYY, M/D/YY, or M/D/YYYY format');
            } else {
                entry.courseCompletedOn = normalizedDate;
            }
        }
        
        return errors;
    }

    private static String normalizeCourseCompletedDate(String rawDate) {
        if (String.isBlank(rawDate)) {
            return null;
        }

        String trimmed = rawDate.trim().replace('"', '');
        if (String.isBlank(trimmed)) {
            return null;
        }

        // Support Excel serial values often found in CSV exports.
        if (Pattern.matches('^\\d+$', trimmed)) {
            try {
                Integer serial = Integer.valueOf(trimmed);
                if (serial > 0) {
                    Date excelBase = Date.newInstance(1899, 12, 30);
                    Date parsed = excelBase.addDays(serial);
                    if (parsed.year() >= 1900 && parsed.year() <= 2100) {
                        return String.valueOf(parsed.month()).leftPad(2, '0') + '/' +
                            String.valueOf(parsed.day()).leftPad(2, '0') + '/' +
                            String.valueOf(parsed.year());
                    }
                }
            } catch (Exception e) {
                // fall through to slash parsing
            }
        }

        String cleaned = trimmed.replace('-', '/').replace('.', '/');
        List<String> parts = cleaned.split('/');
        if (parts.size() != 3) {
            return null;
        }

        try {
            Integer month = Integer.valueOf(parts[0]);
            Integer day = Integer.valueOf(parts[1]);
            Integer year = Integer.valueOf(parts[2]);
            if (parts[2].length() == 2) {
                year = (year >= 50) ? (1900 + year) : (2000 + year);
            }

            if (month < 1 || month > 12 || day < 1 || day > 31 || year < 1900 || year > 2100) {
                return null;
            }

            Date parsed = Date.newInstance(year, month, day);
            if (parsed.month() != month || parsed.day() != day || parsed.year() != year) {
                return null;
            }

            return String.valueOf(month).leftPad(2, '0') + '/' +
                String.valueOf(day).leftPad(2, '0') + '/' +
                String.valueOf(year);
        } catch (Exception e) {
            return null;
        }
    }
    
    // Upload roster file (after validation and user confirmation)
    @AuraEnabled
    public static Map<String, Object> uploadRosterFile(Id rosterUploadId, Id courseId, Id sessionId, String fileName, String base64Data) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            System.debug('uploadRosterFile - rosterUploadId: ' + rosterUploadId);
            System.debug('uploadRosterFile - courseId: ' + courseId);
            System.debug('uploadRosterFile - sessionId: ' + sessionId);
            System.debug('uploadRosterFile - fileName: ' + fileName);
            
            // Get or create the roster upload record
            Roster_Upload__c rosterUpload;
            
            if (rosterUploadId != null) {
                // Record already exists (from startUpload), fetch it
                rosterUpload = [
                    SELECT Id, File_Processed__c, Number_of_Records__c, Successful_Records__c
                    FROM Roster_Upload__c
                    WHERE Id = :rosterUploadId
                    LIMIT 1
                ];
                System.debug('uploadRosterFile - Found existing Roster_Upload__c record with ID: ' + rosterUpload.Id);
            } else {
                // Create new record if it doesn't exist (for manual entry or file upload without pre-creation)
                Session__c session = [SELECT Name, End_Date__c FROM Session__c WHERE Id = :sessionId LIMIT 1];
                Id currentUserId = UserInfo.getUserId();
                String fileProcessedValue = getFileNotProcessedValue();
                
                rosterUpload = new Roster_Upload__c(
                    Session__c = sessionId,
                    Upload_Date__c = Date.today(),
                    Uploaded_By__c = currentUserId,
                    Session_Completion_Date__c = session.End_Date__c
                );
                
                if (fileProcessedValue != null) {
                    rosterUpload.File_Processed__c = fileProcessedValue;
                }
                
                insert rosterUpload;
                System.debug('uploadRosterFile - Created new Roster_Upload__c record with ID: ' + rosterUpload.Id);
            }
            
            // Count records in the file
            List<List<String>> rows = new List<List<String>>();
            if (String.isNotBlank(base64Data)) {
                String csvContent = EncodingUtil.base64Decode(base64Data).toString();
                rows = parseCSV(csvContent);
            }
            
            // Skip header row
            Integer startIndex = 0;
            if (rows.size() > 0) {
                List<String> firstRow = rows[0];
                if (firstRow.size() > 0 && 
                    (firstRow[0].equalsIgnoreCase('First Name') || 
                     firstRow[0].equalsIgnoreCase('firstName') ||
                     firstRow[0].toLowerCase().contains('first'))) {
                    startIndex = 1;
                }
            }
            
            Integer totalRecords = 0;
            for (Integer i = startIndex; i < rows.size(); i++) {
                List<String> row = rows[i];
                Boolean isEmpty = true;
                for (String cell : row) {
                    if (String.isNotBlank(cell)) {
                        isEmpty = false;
                        break;
                    }
                }
                if (!isEmpty) totalRecords++;
            }
            
            // Note: The actual file processing should happen via HTTP callout to external endpoint
            // Similar to VF controller's sendPayload method. For now, we'll just update the status.
            // The VF controller sends the file to Communities_Endpoints__c.CE_Roster_Upload_Endpoint__c
            // and processes the response. This should be implemented when the endpoint is available.
            
            // Mark as processed using the first active picklist value (representing "processed" or "pending")
            String processedValue = getFileProcessedValue();
            if (processedValue != null) {
                rosterUpload.File_Processed__c = processedValue;
            }
            
            // Update record counts
            rosterUpload.Number_of_Records__c = totalRecords;
            rosterUpload.Successful_Records__c = totalRecords; // Will be updated by external processing
            
            update rosterUpload;
            
            System.debug('uploadRosterFile - Updated Roster_Upload__c record ID: ' + rosterUpload.Id);
            System.debug('uploadRosterFile - Total records: ' + totalRecords);
            System.debug('uploadRosterFile - File name: ' + fileName);
            
            result.put('success', 'true');
            result.put('message', 'File uploaded successfully');
            result.put('totalRecords', totalRecords);
            result.put('rosterUploadId', String.valueOf(rosterUpload.Id));
        } catch (Exception e) {
            System.debug('Error in uploadRosterFile: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            result.put('success', 'false');
            result.put('message', 'Error uploading file: ' + e.getMessage());
        }
        
        return result;
    }
}

