public with sharing class CeNewCourseLwcController {
    
    @AuraEnabled(cacheable=true)
    public static NewCourseDataWrapper getNewCourseData(Id courseId, String method) {
        NewCourseDataWrapper wrapper = new NewCourseDataWrapper();
        
        // Get account ID from current user
        User currentUser = [SELECT AccountId, ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        wrapper.accountId = currentUser.AccountId;
        wrapper.contactId = currentUser.ContactId;
        
        // Get course fee
        try {
            PricebookEntry pbe = [SELECT UnitPrice FROM PricebookEntry 
                                  WHERE Product2.ProductCode = 'cer-course' LIMIT 1];
            wrapper.courseFee = pbe.UnitPrice;
        } catch (Exception e) {
            wrapper.courseFee = 35.00;
        }
        
        // Get content from metadata
        try {
            CE_Community_Content__mdt content = [
                SELECT New_Course__c 
                FROM CE_Community_Content__mdt
                WHERE DeveloperName = 'Content' 
                LIMIT 1
            ];
            wrapper.content = formatContentForHTML(content.New_Course__c);
        } catch (Exception e) {
            wrapper.content = '';
        }
        
        // Get dependent picklist map
        wrapper.dependentPicklistMap = getDependentOptions('Course__c', 'Category__c', 'Sub_Category__c');
        
        // If courseId provided, get course data
        if (courseId != null) {
            try {
                Course__c course = [
                    SELECT Course_Name__c, Description__c, Course_Objectives__c, Registration_Phone__c, 
                           Registration_Website__c, Contact__c, Category__c, 
                           Sub_Category__c, Special_Circumstances__c, Account__c
                    FROM Course__c 
                    WHERE Id = :courseId
                    LIMIT 1
                ];
                
                wrapper.course = course;
                
                // If method is null (copy), clone and modify
                if (method == null) {
                    wrapper.course = course.clone(false);
                    wrapper.course.Course_Name__c = course.Course_Name__c + ' - Copy';
                    wrapper.course.Category__c = null;
                    wrapper.course.Sub_Category__c = null;
                    wrapper.isEditMode = false;
                } else if (method == 'Edit') {
                    wrapper.isEditMode = true;
                }
                
                // Set render dependent picklist
                wrapper.renderDependentPicklist = (wrapper.course.Category__c != null) ? 
                    wrapper.dependentPicklistMap.get(wrapper.course.Category__c)?.size() > 0 : false;
                    
            } catch (Exception e) {
                throw new AuraHandledException('Error loading course: ' + e.getMessage());
            }
        } else {
            // New course
            wrapper.course = new Course__c();
            wrapper.course.Account__c = currentUser.AccountId;
            wrapper.renderDependentPicklist = false;
            wrapper.isEditMode = false;
        }
        
        return wrapper;
    }
    
    @AuraEnabled
    public static Map<String, Boolean> checkRenderDependentPicklist(String category) {
        Map<String, Boolean> result = new Map<String, Boolean>();
        Map<String, List<String>> dependentMap = getDependentOptions('Course__c', 'Category__c', 'Sub_Category__c');
        Boolean shouldRender = (category != null) ? dependentMap.get(category)?.size() > 0 : false;
        result.put('renderDependentPicklist', shouldRender);
        return result;
    }
    
    @AuraEnabled
    public static String saveCourseDraft(Course__c course) {
        try {
            course.Status_Selected__c = 'Draft';
            // Contact will be set from wrapper
            Database.upsert(course);
            return course.Id;
        } catch (DmlException e) {
            throw new AuraHandledException('Error saving course: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Error saving course: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static SubmitResponse submitAndPay(Course__c course) {
        SubmitResponse response = new SubmitResponse();
        response.isValid = true;
        response.errors = new Map<String, String>();
        
        // Validate form
        Map<String, String> validationErrors = validateCourse(course);
        if (!validationErrors.isEmpty()) {
            response.isValid = false;
            response.errors = validationErrors;
            return response;
        }
        
        try {
            course.Status_Selected__c = 'Draft';
            Database.upsert(course);
            
            // Create order
            List<Id> orderIds = createOrder(course.Id);
            response.courseId = course.Id;
            response.orderIds = orderIds;
            
        } catch (DmlException e) {
            throw new AuraHandledException('Error submitting course: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Error submitting course: ' + e.getMessage());
        }
        
        return response;
    }
    
    private static Map<String, String> validateCourse(Course__c course) {
        Map<String, String> errors = new Map<String, String>();
        Map<String, List<String>> dependentMap = getDependentOptions('Course__c', 'Category__c', 'Sub_Category__c');
        
        if (String.isBlank(course.Course_Name__c)) {
            errors.put('courseName', 'Course name is required.');
        }
        
        if (String.isBlank(course.Category__c)) {
            errors.put('category', 'You must select a course category from the dropdown list.');
        }
        
        // Check if subcategory is required
        Boolean renderDependentPicklist = (course.Category__c != null) ? 
            dependentMap.get(course.Category__c)?.size() > 0 : false;
        if (renderDependentPicklist && String.isBlank(course.Sub_Category__c)) {
            errors.put('subCategory', 'You must select a course sub category from the dropdown list.');
        }
        
        if (String.isBlank(course.Course_Objectives__c)) {
            errors.put('courseSummary', 'Course Objectives are required.');
        } else if (course.Course_Objectives__c.length() > 500) {
            errors.put('courseSummary', 'Course Objectives cannot exceed 500 characters.');
        }
        
        if (String.isBlank(course.Description__c)) {
            errors.put('description', 'Course Summary is required.');
        } else if (course.Description__c.length() > 500) {
            errors.put('descriptionCount', 'Course Summary cannot exceed 500 characters.');
        }
        
        if (String.isBlank(course.Registration_Phone__c)) {
            errors.put('registrationPhone', 'A course registration contact telephone number is required.');
        }
        
        return errors;
    }
    
    private static List<Id> createOrder(Id courseId) {
        User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Id accountId = currentUser.AccountId;
        
        List<OrderItem> existingOrderItems = [
            SELECT OrderId 
            FROM OrderItem
            WHERE Order.Status = 'Draft'
            AND Course__c = :courseId
            AND PricebookEntry.Product2.ProductCode = 'cer-course'
            AND Order.AccountId = :accountId
        ];
        
        Set<Id> orderIds = new Set<Id>();
        
        if (existingOrderItems.isEmpty()) {
            PricebookEntry pbe = [
                SELECT UnitPrice, Pricebook2Id 
                FROM PricebookEntry
                WHERE Product2.ProductCode = 'cer-course' 
                LIMIT 1
            ];
            
            Order newOrder = new Order(
                AccountId = accountId,
                EffectiveDate = System.today(),
                OwnerId = UserInfo.getUserId(),
                Pricebook2Id = pbe.Pricebook2Id,
                Status = 'Draft'
            );
            
            Database.insert(newOrder);
            
            Database.insert(new OrderItem(
                Course__c = courseId,
                OrderId = newOrder.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = pbe.UnitPrice
            ));
            
            orderIds.add(newOrder.Id);
        } else {
            for (OrderItem oi : existingOrderItems) {
                orderIds.add(oi.OrderId);
            }
        }
        
        return new List<Id>(orderIds);
    }
    
    private static Map<String, List<String>> getDependentOptions(String objectName, String controllingField, String dependentField) {
        Map<String, List<String>> dependentOptionsMap = new Map<String, List<String>>();
        
        try {
            // Get field describe information
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
            if (objType == null) {
                return dependentOptionsMap;
            }
            
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
            
            Schema.SObjectField controllingFieldInfo = fieldMap.get(controllingField);
            Schema.SObjectField dependentFieldInfo = fieldMap.get(dependentField);
            
            if (controllingFieldInfo == null || dependentFieldInfo == null) {
                return dependentOptionsMap;
            }
            
            Schema.DescribeFieldResult controllingFieldDescribe = controllingFieldInfo.getDescribe();
            Schema.DescribeFieldResult dependentFieldDescribe = dependentFieldInfo.getDescribe();
            
            List<Schema.PicklistEntry> controllingValues = controllingFieldDescribe.getPicklistValues();
            List<Schema.PicklistEntry> dependentValues = dependentFieldDescribe.getPicklistValues();
            
            // Build dependency map by querying existing records
            // This approach works around the validFor property access issue
            Set<String> categorySet = new Set<String>();
            for (Schema.PicklistEntry entry : controllingValues) {
                categorySet.add(entry.getValue());
                dependentOptionsMap.put(entry.getValue(), new List<String>());
            }
            
            // Query existing Course records to find valid combinations
            String query = 'SELECT ' + String.escapeSingleQuotes(controllingField) + ', ' + 
                          String.escapeSingleQuotes(dependentField) + 
                          ' FROM ' + String.escapeSingleQuotes(objectName) + 
                          ' WHERE ' + String.escapeSingleQuotes(controllingField) + ' != null' +
                          ' AND ' + String.escapeSingleQuotes(dependentField) + ' != null' +
                          ' LIMIT 10000';
            
            List<SObject> records = Database.query(query);
            Map<String, Set<String>> tempMap = new Map<String, Set<String>>();
            
            for (SObject record : records) {
                String category = (String)record.get(controllingField);
                String subCategory = (String)record.get(dependentField);
                
                if (category != null && subCategory != null) {
                    if (!tempMap.containsKey(category)) {
                        tempMap.put(category, new Set<String>());
                    }
                    tempMap.get(category).add(subCategory);
                }
            }
            
            // Populate the map from queried data
            for (String category : dependentOptionsMap.keySet()) {
                if (tempMap.containsKey(category)) {
                    dependentOptionsMap.put(category, new List<String>(tempMap.get(category)));
                }
            }
            
            // If no records exist, return all dependent values for each controlling value
            // (fallback - not ideal but prevents empty dropdowns)
            if (records.isEmpty()) {
                for (String category : dependentOptionsMap.keySet()) {
                    List<String> allSubCategories = new List<String>();
                    for (Schema.PicklistEntry entry : dependentValues) {
                        allSubCategories.add(entry.getValue());
                    }
                    dependentOptionsMap.put(category, allSubCategories);
                }
            }
            
        } catch (Exception e) {
            // If there's any error, return empty map
            System.debug('Error in getDependentOptions: ' + e.getMessage());
        }
        
        return dependentOptionsMap;
    }
    
    private static String formatContentForHTML(String content) {
        if (String.isBlank(content)) {
            return '';
        }
        return content;
    }
    
    // Wrapper classes
    public class NewCourseDataWrapper {
        @AuraEnabled public Course__c course;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public Decimal courseFee;
        @AuraEnabled public String content;
        @AuraEnabled public Map<String, List<String>> dependentPicklistMap;
        @AuraEnabled public Boolean renderDependentPicklist;
        @AuraEnabled public Boolean isEditMode;
    }
    
    public class SubmitResponse {
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public Map<String, String> errors;
        @AuraEnabled public Id courseId;
        @AuraEnabled public List<Id> orderIds;
    }
}