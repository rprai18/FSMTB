public with sharing class CEActionController {
    private static Set<Id> adminIds = new Map<Id, Profile>([SELECT Id,Name FROM Profile WHERE Name IN ('FSMTB Administrator', 'System Administrator', 'DEG API User')]).keySet();
    private static Map<String, List<String>> dependentPicklistMap = Utils.getDependentOptions('Course__c', 'Category__c', 'Sub_Category__c');


    @AuraEnabled
    public static List<String> getAvailableActions(Id recordId) {
        String objectName = recordId.getSobjectType().getDescribe().getName();
        List<String> options = new List<String>();

        System.debug(UserInfo.getProfileId());
        System.debug(adminIds);

        if (objectName.equals('Account')) {
            // Only allow non-Provisional actions for Accounts
            // Provisional status is now tracked in Registration_Status__c field, not in Action Status
            for (Schema.PicklistEntry ple : CE_Action__c.Action__c.getDescribe().getPicklistValues()) {
                String actionValue = ple.getValue();
                
                // Allow only specific action statuses (no Provisional-related actions)
                if (actionValue.equals('Revoked') && adminIds.contains(UserInfo.getProfileId())) {
                    options.add(actionValue);
                } else if (actionValue.equals('Restricted')) {
                    options.add(actionValue);
                } else if (actionValue.equals('Under Review')) {
                    options.add(actionValue);
                } else if (actionValue.equals('Internal Investigation')) {
                    options.add(actionValue);
                }
                
                // Explicitly exclude Provisional-related actions:
                // - Provisional
                // - Provisional & Restricted
                // - Provisional & Under Review
                // - Provisional & Internal Investigation
            }
        } else if (objectName.equals('Course__c') || objectName.equals('Session__c')) {
            for (Schema.PicklistEntry ple : CE_Action__c.Action__c.getDescribe().getPicklistValues()) {
                if (ple.getValue().equals('Revoked') && adminIds.contains(UserInfo.getProfileId())) options.add(ple.getValue());
                if (ple.getValue().equals('Restricted')) options.add(ple.getValue());
                if (ple.getValue().equals('Denied')) options.add(ple.getValue());
                if (ple.getValue().equals('Under Review')) options.add(ple.getValue());
            }
        } else if (objectName.equals('Professional_Continuing_Education__c')) {
            for (Schema.PicklistEntry ple : CE_Action__c.Action__c.getDescribe().getPicklistValues()) {
                if (ple.getValue().equals('Revoked') && adminIds.contains(UserInfo.getProfileId())) options.add(ple.getValue());
            }
        }

        return options;
    }


    @AuraEnabled
    public static List<CE_Action__c> getCeActions(Id recordId) {
        String objectName = recordId.getSobjectType().getDescribe().getName();
        List<CE_Action__c> actions = new List<CE_Action__c>();

        if (objectName == 'Account') {
            actions = [
                    SELECT Name,Active__c,Action__c,Start_Date__c,End_Date__c,Reason__c
                    FROM CE_Action__c
                    WHERE Account__c = :recordId
                    ORDER BY End_Date__c DESC NULLS FIRST
            ];
        } else if (objectName == 'Course__c') {
            actions = [
                    SELECT Name,Active__c,Action__c,Start_Date__c,End_Date__c,Reason__c,Course__r.Category__c,Course__r.Sub_Category__c
                    FROM CE_Action__c
                    WHERE Course__c = :recordId
                    ORDER BY End_Date__c DESC NULLS FIRST
            ];
        } else if (objectName == 'Session__c') {
            actions = [
                    SELECT Name,Active__c,Action__c,Start_Date__c,End_Date__c,Reason__c
                    FROM CE_Action__c
                    WHERE Session__c = :recordId
                    ORDER BY End_Date__c DESC NULLS FIRST
            ];
        } else if (objectName == 'Professional_Continuing_Education__c') {
            actions = [
                    SELECT Name,Active__c,Action__c,Start_Date__c,End_Date__c,Reason__c
                    FROM CE_Action__c
                    WHERE Professional_Continuing_Education__c = :recordId
                    ORDER BY End_Date__c DESC NULLS FIRST
            ];
        }

        return actions;
    }

    @AuraEnabled
    public static void submitAction(Id recordId, String actionTaken, String startDate, String reason) {
        String objectName = recordId.getSobjectType().getDescribe().getName();
        
        // Validate that Provisional actions cannot be created for Accounts
        if (objectName.equals('Account')) {
            if (actionTaken != null && (
                actionTaken.equals('Provisional') ||
                actionTaken.contains('Provisional &') ||
                actionTaken.contains('Provisional&') ||
                actionTaken.toLowerCase().contains('provisional')
            )) {
                throw new AuraHandledException('Provisional: Provisional actions are no longer allowed. Provisional status is now tracked in Registration Status field.');
            }
        }
        
        CE_Action__c action = new CE_Action__c(
                Active__c = true,
                Action__c = actionTaken,
                Start_Date__c = Date.valueOf(startDate),
                Reason__c = reason
        );

        if (objectName.equals('Account')) {
            action.Account__c = recordId;
        } else if (objectName.equals('Course__c')) {
            action.Course__c = recordId;
        } else if (objectName.equals('Session__c')) {
            action.Session__c = recordId;
        } else if (objectName.equals('Professional_Continuing_Education__c')) {
            action.Professional_Continuing_Education__c = recordId;
        }

        Database.insert(action);

        updateParentRecord(objectName, recordId, action);
        deactivateSiblingActions(objectName, recordId, action);

        if (action.Action__c.equals('Denied')) sendDenialEmail(action.Id, objectName);
    }

    @AuraEnabled
    public static String getCategories() {
        return JSON.serialize(new MapWrapper(dependentPicklistMap));
    }

    private class MapWrapper {
        public List<String> categories {get; private set;}
        public List<List<String>> subCategories {get; private set;}

        public MapWrapper(Map<String, List<String>> picklists) {
            Set<String> categoryKeys = picklists.keySet();
            categoryKeys.remove('Other');

            categories = new List<String>(categoryKeys);
            subCategories = new List<List<String>>(picklists.values());
        }
    }

    @AuraEnabled
    public static void endCurrentAction(Id recordId, Id actionId, String endDate, String reason, String category, String subCategory) {
        String objectName = recordId.getSobjectType().getDescribe().getName();
        CE_Action__c action = new CE_Action__c(
                Id = actionId,
                Active__c = false,
                End_Date__c = Date.valueOf(endDate),
                Reason__c = reason
        );

        Savepoint sp = Database.setSavepoint();
        try {
            Boolean pendingCourseEnded = [
                    SELECT Action__c
                    FROM CE_Action__c
                    WHERE Id = :actionId
            ].Action__c == 'Pending';

            System.debug(category);

            Database.update(action);
            if (category != null) {
                Course__c c = new Course__c(
                        Id = [SELECT Course__c FROM CE_Action__c WHERE Id = :actionId LIMIT 1].Course__c,
                        Category__c = category,
                        Sub_Category__c = subCategory
                );

                System.debug(JSON.serializePretty(c));

                Database.update(c);

                if (pendingCourseEnded) {
                    sendCourseCategoryUpdatedEmail(actionId, objectName, c.Id);
                }

            }

            resetParentStatus(recordId);
        } catch (DmlException e) {
            Database.rollback(sp);
        }
    }

    private static void updateParentRecord(String objectName, Id recordId, CE_Action__c action) {
        SObject record;

        if (objectName.equals('Account')) {
            Account account = [SELECT Current_Active_Action_Status__c FROM Account WHERE Id = :recordId];
            
            // Only update Action Status for non-Provisional actions
            // Provisional status is now tracked in Registration_Status__c, not Action Status
            if (action.Action__c != null && 
                !action.Action__c.equals('Provisional') && 
                !action.Action__c.contains('Provisional')) {
                
                // Only allow specific action statuses
                if (action.Action__c.equals('Under Review') ||
                    action.Action__c.equals('Restricted') ||
                    action.Action__c.equals('Internal Investigation') ||
                    action.Action__c.equals('Revoked')) {
                    
                    account.Current_Active_Action_Status__c = action.Action__c;
                    account.Current_Active_Action_Start_Date__c = action.Start_Date__c;
                }
            }
            
            record = account;
        } else if (objectName.equals('Course__c')) {
            Course__c course = [SELECT Current_Active_Action_Status__c FROM Course__c WHERE Id = :recordId];
            course.Current_Active_Action_Status__c = action.Action__c;
            course.Current_Active_Action_Start_Date__c = action.Start_Date__c;
            record = course;
        } else if (objectName.equals('Session__c')) {
            Session__c session = [SELECT Current_Active_Action_Status__c FROM Session__c WHERE Id = :recordId];
            session.Current_Active_Action_Status__c = action.Action__c;
            session.Current_Active_Action_Start_Date__c = action.Start_Date__c;
            record = session;
        } else if (objectName.equals('Professional_Continuing_Education__c')) {
            Professional_Continuing_Education__c pce = [SELECT Current_Active_Action_Status__c FROM Professional_Continuing_Education__c WHERE Id = :recordId];
            pce.Current_Active_Action_Status__c = action.Action__c;
            pce.Current_Active_Action_Start_Date__c = action.Start_Date__c;
            record = pce;
        }

        Database.update(record);
    }

    private static void deactivateSiblingActions(String objectName, Id recordId, CE_Action__c action) {
        List<CE_Action__c> actions = new List<CE_Action__c>();

        if (objectName.equals('Account')) {
            actions = [SELECT Active__c FROM CE_Action__c WHERE Account__c = :recordId AND Id != :action.Id AND Active__c = TRUE];
        } else if (objectName.equals('Course__c')) {
            actions = [SELECT Active__c FROM CE_Action__c WHERE Course__c = :recordId AND Id != :action.Id AND Active__c = TRUE];
        } else if (objectName.equals('Session__c')) {
            actions = [SELECT Active__c FROM CE_Action__c WHERE Session__c = :recordId AND Id != :action.Id AND Active__c = TRUE];
        } else if (objectName.equals('Professional_Continuing_Education__c')) {
            actions = [SELECT Active__c FROM CE_Action__c WHERE Professional_Continuing_Education__c = :recordId AND Id != :action.Id AND Active__c = TRUE];
        }

        if (actions.size() > 0) {
            for (CE_Action__c act : actions) {
                act.Active__c = false;
                act.End_Date__c = System.today();
            }

            Database.update(actions);
        }
    }

    private static void resetParentStatus(Id recordId) {
        String objectName = recordId.getSobjectType().getDescribe().getName();
        SObject obj;

        if (objectName.equals('Account')) {
            Account account = [SELECT Current_Active_Action_Status__c FROM Account WHERE Id = :recordId];
            account.Current_Active_Action_Status__c = null;
            account.Current_Active_Action_Start_Date__c = null;
            obj = account;
        } else if (objectName.equals('Course__c')) {
            Course__c course = [Select Current_Active_Action_Status__c From Course__c Where Id = :recordId];
            course.Current_Active_Action_Status__c = null;
            course.Current_Active_Action_Start_Date__c = null;
            obj = course;
        } else if (objectName.equals('Session__c')) {
            Session__c session = [Select Current_Active_Action_Status__c From Session__c Where Id = :recordId];
            session.Current_Active_Action_Status__c = null;
            session.Current_Active_Action_Start_Date__c = null;
            obj = session;
        } else if (objectName.equals('Professional_Continuing_Education__c')) {
            Professional_Continuing_Education__c pce = [Select Current_Active_Action_Status__c From Professional_Continuing_Education__c Where Id = :recordId];
            pce.Current_Active_Action_Status__c = null;
            pce.Current_Active_Action_Start_Date__c = null;
            obj = pce;
        }

        Database.update(obj);
    }

    private static void sendDenialEmail(Id actionId, String objectName) {
        Id userId = getUserId(actionId, objectName);
        String templateName = objectName == 'Course__c' ? 'Course_Denial' : 'CE_Session_Denied';
        CommunityUtil.sendEmail(userId, templateName, actionId, getEmailRecipients(userId));
    }

    private static void sendCourseCategoryUpdatedEmail(Id actionId, String objectName, Id courseId) {
        Id userId = getUserId(actionId, objectName);
        String templateName = 'Coursework_Category_Updated_Email';
        CommunityUtil.sendEmail(userId, templateName, courseId, getEmailRecipients(userId));
    }

    private static Id getUserId(Id actionId, String objectName) {
        return (objectName == 'Course__c')
                ? [SELECT Course__r.CreatedById FROM CE_Action__c WHERE Id = :actionId LIMIT 1].Course__r.CreatedById
                : [SELECT Session__r.CreatedById FROM CE_Action__c WHERE Id = :actionId LIMIT 1][0].Session__r.CreatedById;
    }

    private static List<String> getEmailRecipients(Id userId) {
        List<String> emailRecipients = new List<String>();
        emailRecipients.add([SELECT Email FROM User WHERE Id = :userId LIMIT 1][0].Email);
        return emailRecipients;
    }
}