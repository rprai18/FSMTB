public without sharing class CeCommunityPaymentLwcController {
    
    // Wrapper class for payment data
    public class PaymentDataWrapper {
        @AuraEnabled public String feeContent;
        @AuraEnabled public String content;
        @AuraEnabled public Double amount;
        @AuraEnabled public List<StateOption> stateOptions;
        @AuraEnabled public List<YearOption> yearOptions;
        @AuraEnabled public String error;
    }
    
    // Wrapper class for state options
    public class StateOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        
        public StateOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
    
    // Wrapper class for year options
    public class YearOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        
        public YearOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
    
    // Wrapper class for payment response
    public class PaymentResponseWrapper {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String redirectUrl;
        @AuraEnabled public String emailStatus; // Status of password reset email
        @AuraEnabled public String userCreated; // User ID if created
        @AuraEnabled public String emailAddress; // Email address where email was sent
        
        public PaymentResponseWrapper(Boolean success, String message, String redirectUrl) {
            this.success = success;
            this.message = message;
            this.redirectUrl = redirectUrl;
            this.emailStatus = '';
            this.userCreated = '';
            this.emailAddress = '';
        }
    }
    
    /**
     * Get payment data including content, amount, fee content, state and year options
     */
    @AuraEnabled(cacheable=false)
    public static PaymentDataWrapper getPaymentData(List<Id> orderIds) {
        PaymentDataWrapper wrapper = new PaymentDataWrapper();
        
        try {
            if (orderIds == null || orderIds.isEmpty()) {
                wrapper.error = 'No order IDs provided.';
                return wrapper;
            }
            
            // Get purchase type
            CommunityOrderProcessor.PurchaseType pType = CommunityOrderProcessor.getPurchaseType(orderIds[0]);
            
            // Get content from metadata
            wrapper.content = getContentForPurchaseType(pType);
            wrapper.feeContent = getFeeContentForPurchaseType(pType);
            
            // Get amount from orders
            wrapper.amount = calculateAmount(orderIds);
            
            // Get state options
            wrapper.stateOptions = getStateOptions();
            
            // Get year options (25 years from current year)
            wrapper.yearOptions = getYearOptions();
            
        } catch (Exception e) {
            wrapper.error = 'Error loading payment data: ' + e.getMessage();
            System.debug('Error in getPaymentData: ' + e.getStackTraceString());
        }
        
        return wrapper;
    }
    
    /**
     * Get content based on purchase type
     */
    private static String getContentForPurchaseType(CommunityOrderProcessor.PurchaseType pType) {
        String content = '';
        
        try {
            if (pType == CommunityOrderProcessor.PurchaseType.CE_FEEDBACK) {
                List<CE_Community_Content__mdt> contentMdtList = [SELECT Feedback_Payment__c 
                                                                   FROM CE_Community_Content__mdt 
                                                                   WHERE DeveloperName = 'Content' 
                                                                   LIMIT 1];
                if (!contentMdtList.isEmpty()) {
                    content = contentMdtList[0].Feedback_Payment__c;
                }
            } else if (pType == CommunityOrderProcessor.PurchaseType.CE_COURSE) {
                List<CE_Community_Content__mdt> contentMdtList = [SELECT Payment_Course__c 
                                                                   FROM CE_Community_Content__mdt 
                                                                   WHERE DeveloperName = 'Content' 
                                                                   LIMIT 1];
                if (!contentMdtList.isEmpty()) {
                    content = contentMdtList[0].Payment_Course__c;
                }
            } else if (pType == CommunityOrderProcessor.PurchaseType.CE_MEMBERSHIP) {
                List<CE_Community_Content__mdt> contentMdtList = [SELECT Payment_Signup__c 
                                                                   FROM CE_Community_Content__mdt 
                                                                   WHERE DeveloperName = 'Content' 
                                                                   LIMIT 1];
                if (!contentMdtList.isEmpty()) {
                    content = contentMdtList[0].Payment_Signup__c;
                }
            } else if (pType == CommunityOrderProcessor.PurchaseType.CE_RENEWAL) {
                List<CE_Community_Content__mdt> contentMdtList = [SELECT Renewal__c 
                                                                   FROM CE_Community_Content__mdt 
                                                                   WHERE DeveloperName = 'Content' 
                                                                   LIMIT 1];
                if (!contentMdtList.isEmpty()) {
                    content = contentMdtList[0].Renewal__c;
                }
            } else if (pType == CommunityOrderProcessor.PurchaseType.MLVC_MEMBERSHIP) {
                List<MLVC_Community_Content__mdt> contentMdtList = [SELECT Payment__c 
                                                                     FROM MLVC_Community_Content__mdt 
                                                                     WHERE DeveloperName = 'Content' 
                                                                     LIMIT 1];
                if (!contentMdtList.isEmpty()) {
                    content = contentMdtList[0].Payment__c;
                }
            }
        } catch (Exception e) {
            System.debug('Error getting content: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
        }
        
        if (content != null) {
            content = content.escapeHtml4().replaceAll('\r\n', '<br />');
        }
        
        return content;
    }
    
    /**
     * Get fee content label based on purchase type
     */
    private static String getFeeContentForPurchaseType(CommunityOrderProcessor.PurchaseType pType) {
        String feeContent = '';
        
        if (pType == CommunityOrderProcessor.PurchaseType.CE_FEEDBACK) {
            feeContent = 'Feedback Fee: ';
        } else if (pType == CommunityOrderProcessor.PurchaseType.CE_COURSE) {
            feeContent = 'Course Upload Fee: ';
        } else if (pType == CommunityOrderProcessor.PurchaseType.CE_MEMBERSHIP) {
            feeContent = 'Provider Registration Fee: ';
        } else if (pType == CommunityOrderProcessor.PurchaseType.CE_RENEWAL) {
            feeContent = 'Provider Renewal Fee: ';
        } else if (pType == CommunityOrderProcessor.PurchaseType.MLVC_MEMBERSHIP) {
            feeContent = 'MLVC Registration Fee: ';
        }
        
        return feeContent;
    }
    
    /**
     * Calculate total amount from orders
     */
    private static Double calculateAmount(List<Id> orderIds) {
        Double amount = 0;
        
        try {
            String accountId = null;
            String ownerId = null;
            
            // Get AccountId from current user
            try {
                List<User> users = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
                if (!users.isEmpty() && users[0].AccountId != null) {
                    accountId = users[0].AccountId;
                }
            } catch (Exception e) {
                System.debug('Error getting AccountId from User: ' + e.getMessage());
            }
            
            // Get owner ID
            if (accountId == null) {
                // For guest users, try to get DEG Admin1 user
                try {
                    List<User> owners = [SELECT Id FROM User WHERE Name = 'DEG Admin1' LIMIT 1];
                    if (!owners.isEmpty()) {
                        ownerId = owners[0].Id;
                    } else {
                        ownerId = UserInfo.getUserId();
                    }
                } catch (Exception e) {
                    System.debug('Error getting owner User: ' + e.getMessage());
                    ownerId = UserInfo.getUserId();
                }
            } else {
                ownerId = UserInfo.getUserId();
            }
            
            // If accountId is still null, try to get "New Membership Account"
            if (accountId == null) {
                try {
                    List<Account> tempAccounts = [SELECT Id FROM Account WHERE Name = 'New Membership Account' LIMIT 1];
                    if (!tempAccounts.isEmpty()) {
                        accountId = tempAccounts[0].Id;
                    }
                } catch (Exception e) {
                    System.debug('Error getting New Membership Account: ' + e.getMessage());
                }
            }
            
            // Query orders with OrderItems to calculate amount dynamically
            // This matches the original VF controller pattern
            List<Order> orders = new List<Order>();
            
            // Query orders with OrderItems - works for both guest and logged-in users
            // Include Quantity in OrderItems subquery for accurate calculation
            orders = [
                SELECT Id, TotalAmount, AccountId, OwnerId,
                       (SELECT Id, UnitPrice, Quantity 
                        FROM OrderItems)
                FROM Order 
                WHERE Id IN :orderIds 
                AND Status = 'Draft'
            ];
            
            System.debug('calculateAmount - Found ' + orders.size() + ' orders for IDs: ' + orderIds);
            
            for (Order o : orders) {
                // Use TotalAmount if available, otherwise calculate from OrderItems
                if (o.TotalAmount != null && o.TotalAmount > 0) {
                    amount += o.TotalAmount;
                    System.debug('calculateAmount - Using TotalAmount: ' + o.TotalAmount);
                } else if (o.OrderItems != null && !o.OrderItems.isEmpty()) {
                    // Calculate from OrderItems (matching original VF controller logic)
                    Double orderTotal = 0;
                    for (OrderItem oi : o.OrderItems) {
                        Double itemTotal = (oi.UnitPrice != null ? oi.UnitPrice : 0) * (oi.Quantity != null ? oi.Quantity : 1);
                        orderTotal += itemTotal;
                    }
                    amount += orderTotal;
                    System.debug('calculateAmount - Calculated from OrderItems: ' + orderTotal + ' (Order ID: ' + o.Id + ')');
                } else {
                    System.debug('calculateAmount - Warning: Order ' + o.Id + ' has no TotalAmount and no OrderItems');
                }
            }
            
            System.debug('calculateAmount - Final total amount: ' + amount);
        } catch (Exception e) {
            System.debug('Error calculating amount: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
        }
        
        return amount;
    }
    
    /**
     * Get state options - using full state names as in registration form
     */
    private static List<StateOption> getStateOptions() {
        List<StateOption> options = new List<StateOption>();
        
        // Add all US states and territories (matching cEregistrationForm pattern)
        options.add(new StateOption('Alabama', 'Alabama'));
        options.add(new StateOption('Alaska', 'Alaska'));
        options.add(new StateOption('Arkansas', 'Arkansas'));
        options.add(new StateOption('American Samoa', 'American Samoa'));
        options.add(new StateOption('Arizona', 'Arizona'));
        options.add(new StateOption('California', 'California'));
        options.add(new StateOption('Colorado', 'Colorado'));
        options.add(new StateOption('Connecticut', 'Connecticut'));
        options.add(new StateOption('District of Columbia', 'District of Columbia'));
        options.add(new StateOption('Delaware', 'Delaware'));
        options.add(new StateOption('Florida', 'Florida'));
        options.add(new StateOption('Georgia', 'Georgia'));
        options.add(new StateOption('Guam', 'Guam'));
        options.add(new StateOption('Hawaii', 'Hawaii'));
        options.add(new StateOption('Iowa', 'Iowa'));
        options.add(new StateOption('Idaho', 'Idaho'));
        options.add(new StateOption('Illinois', 'Illinois'));
        options.add(new StateOption('Indiana', 'Indiana'));
        options.add(new StateOption('Kansas', 'Kansas'));
        options.add(new StateOption('Kentucky', 'Kentucky'));
        options.add(new StateOption('Louisiana', 'Louisiana'));
        options.add(new StateOption('Massachusetts', 'Massachusetts'));
        options.add(new StateOption('Maryland', 'Maryland'));
        options.add(new StateOption('Maine', 'Maine'));
        options.add(new StateOption('Michigan', 'Michigan'));
        options.add(new StateOption('Minnesota', 'Minnesota'));
        options.add(new StateOption('Missouri', 'Missouri'));
        options.add(new StateOption('Northern Mariana Islands', 'Northern Mariana Islands'));
        options.add(new StateOption('Mississippi', 'Mississippi'));
        options.add(new StateOption('Montana', 'Montana'));
        options.add(new StateOption('North Carolina', 'North Carolina'));
        options.add(new StateOption('North Dakota', 'North Dakota'));
        options.add(new StateOption('Nebraska', 'Nebraska'));
        options.add(new StateOption('New Hampshire', 'New Hampshire'));
        options.add(new StateOption('New Jersey', 'New Jersey'));
        options.add(new StateOption('New Mexico', 'New Mexico'));
        options.add(new StateOption('Nevada', 'Nevada'));
        options.add(new StateOption('New York', 'New York'));
        options.add(new StateOption('Ohio', 'Ohio'));
        options.add(new StateOption('Oklahoma', 'Oklahoma'));
        options.add(new StateOption('Oregon', 'Oregon'));
        options.add(new StateOption('Pennsylvania', 'Pennsylvania'));
        options.add(new StateOption('Puerto Rico', 'Puerto Rico'));
        options.add(new StateOption('Rhode Island', 'Rhode Island'));
        options.add(new StateOption('South Carolina', 'South Carolina'));
        options.add(new StateOption('South Dakota', 'South Dakota'));
        options.add(new StateOption('Tennessee', 'Tennessee'));
        options.add(new StateOption('Texas', 'Texas'));
        options.add(new StateOption('Utah', 'Utah'));
        options.add(new StateOption('Virginia', 'Virginia'));
        options.add(new StateOption('US Virgin Islands', 'US Virgin Islands'));
        options.add(new StateOption('Vermont', 'Vermont'));
        options.add(new StateOption('Washington', 'Washington'));
        options.add(new StateOption('Wisconsin', 'Wisconsin'));
        options.add(new StateOption('West Virginia', 'West Virginia'));
        options.add(new StateOption('Wyoming', 'Wyoming'));
        
        return options;
    }
    
    /**
     * Get year options (25 years from current year)
     */
    private static List<YearOption> getYearOptions() {
        List<YearOption> options = new List<YearOption>();
        Integer currentYear = System.today().year();
        
        for (Integer i = 0; i < 25; i++) {
            String year = String.valueOf(currentYear + i);
            options.add(new YearOption(year, year));
        }
        
        return options;
    }
    
    /**
     * Submit payment - wraps the REST endpoint logic
     */
    @AuraEnabled
    public static PaymentResponseWrapper submitPayment(String ccn, String month, String year, String cvn, 
                                                      String firstName, String lastName, String address,
                                                      String city, String state, String postalCode, 
                                                      List<Id> orderIds, Id accountId, Id contactId) {
        // Note: System.debug logs won't be visible for guest users
        // All important information should be returned in the response message
        System.debug('========== submitPayment METHOD CALLED ==========');
        System.debug('Parameters received:');
        System.debug('  ccn: ' + (ccn != null ? ccn.substring(0, Math.min(4, ccn.length())) + '****' : 'null'));
        System.debug('  month: ' + month);
        System.debug('  year: ' + year);
        System.debug('  cvn: ' + (cvn != null ? '***' : 'null'));
        System.debug('  firstName: ' + firstName);
        System.debug('  lastName: ' + lastName);
        System.debug('  address: ' + address);
        System.debug('  city: ' + city);
        System.debug('  state: ' + state);
        System.debug('  postalCode: ' + postalCode);
        System.debug('  orderIds: ' + orderIds);
        System.debug('  orderIds size: ' + (orderIds != null ? orderIds.size() : 0));
        System.debug('==================================================');
        
        try {
            if (orderIds == null || orderIds.isEmpty()) {
                System.debug('ERROR: No order IDs provided');
                return new PaymentResponseWrapper(false, 'There was no order submitted to process', null);
            }
            
            System.debug('Step 1: Validating orderIds - passed');
            
            // Get user's AccountId - use helper class to bypass sharing if needed
            List<User> currentUsers = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            String currentUserAccountId = null;
            if (!currentUsers.isEmpty()) {
                currentUserAccountId = currentUsers[0].AccountId;
            }
            
            // Get orders
            String ownerId;
            
            if (currentUserAccountId == null) {
                // For guest users, try to get DEG Admin1 user
                try {
                    List<User> owners = [SELECT Id FROM User WHERE Name = 'DEG Admin1' LIMIT 1];
                    if (!owners.isEmpty()) {
                        ownerId = owners[0].Id;
                    } else {
                        ownerId = UserInfo.getUserId();
                    }
                } catch (Exception e) {
                    System.debug('Error getting owner User: ' + e.getMessage());
                    ownerId = UserInfo.getUserId();
                }
            } else {
                ownerId = UserInfo.getUserId();
            }
            
            // Use preserved accountId from registration if provided, otherwise use current user's AccountId (for renewals)
            Id accountIdToUse = accountId; // Use preserved AccountId from registration (for new registrations)
            if (accountIdToUse == null) {
                accountIdToUse = currentUserAccountId; // Fall back to current user's AccountId (for renewals)
            }
            
            if (accountIdToUse == null) {
                List<Account> tempAccounts = [SELECT Id FROM Account WHERE Name = 'New Membership Account' LIMIT 1];
                if (!tempAccounts.isEmpty()) {
                    accountIdToUse = tempAccounts[0].Id;
                }
            }
            
            // Verify user has access to the Account (for renewals)
            // If accountIdToUse exists and doesn't match user's AccountId, verify it's accessible
            String userAccountId = (!currentUsers.isEmpty() && currentUsers[0].AccountId != null) ? currentUsers[0].AccountId : null;
            if (accountIdToUse != null && userAccountId != null && userAccountId != accountIdToUse) {
                // For renewals, the Order's AccountId should match user's AccountId
                // Query the first order to check its AccountId
                try {
                    List<Order> firstOrderCheck = AccountUpdateHelper.getOrdersByIds(new List<Id>{orderIds[0]}, null, ownerId);
                    if (!firstOrderCheck.isEmpty() && firstOrderCheck[0].AccountId != null) {
                        // Use the AccountId from the Order
                        accountIdToUse = firstOrderCheck[0].AccountId;
                        System.debug('Using AccountId from Order: ' + accountIdToUse);
                    }
                } catch (Exception e) {
                    System.debug('Error checking Order AccountId: ' + e.getMessage());
                }
            }
            
            // Query orders - for guest users (new registrations), query by Order IDs only
            // For logged-in users (renewals), try with AccountId/OwnerId filters first
            List<Order> orders = new List<Order>();
            
            // First, try querying with filters if we have accountIdToUse (for logged-in users)
            if (accountIdToUse != null && userAccountId != null && userAccountId == accountIdToUse) {
                System.debug('Querying orders for logged-in user with AccountId: ' + accountIdToUse);
                orders = AccountUpdateHelper.getOrdersByIds(orderIds, accountIdToUse, ownerId);
            }
            
            // If no orders found or for guest users, query by Order IDs only (no AccountId/OwnerId filter)
            if (orders.isEmpty()) {
                System.debug('Querying orders by IDs only (for guest users or if filtered query returned no results)');
                orders = [
                    SELECT Id, TotalAmount, AccountId, Status, OwnerId, Pricebook2Id,
                           (SELECT Id, PricebookEntryId, Product2Id, Product2.ProductCode, 
                                   Membership__c, Order.Lead__c, Course__c, 
                                   UnitPrice, Quantity, Course_Name__c, Course__r.Name 
                            FROM OrderItems),
                           Lead__c
                    FROM Order
                    WHERE Id IN :orderIds
                    AND Status = 'Draft'
                ];
                
                // Don't update orders here - wait until after payment is successful
                // Updating orders before callout causes "uncommitted work pending" error
                if (!orders.isEmpty()) {
                    System.debug('Found ' + orders.size() + ' orders by ID only');
                }
            } else {
                System.debug('Found ' + orders.size() + ' orders with AccountId/OwnerId filters');
            }
            
            if (orders == null || orders.isEmpty()) {
                System.debug('No orders found for Order IDs: ' + orderIds);
                return new PaymentResponseWrapper(false, 'No valid orders found', null);
            }
            
            // Calculate charge amount - use TotalAmount if available, otherwise calculate from OrderItems
            Double chargeAmount = 0;
            for (Order o : orders) {
                if (o.TotalAmount != null && o.TotalAmount > 0) {
                    chargeAmount += o.TotalAmount;
                    System.debug('submitPayment - Using TotalAmount: ' + o.TotalAmount);
                } else if (o.OrderItems != null && !o.OrderItems.isEmpty()) {
                    // Calculate from OrderItems (matching original VF controller logic)
                    Double orderTotal = 0;
                    for (OrderItem oi : o.OrderItems) {
                        Double itemTotal = (oi.UnitPrice != null ? oi.UnitPrice : 0) * (oi.Quantity != null ? oi.Quantity : 1);
                        orderTotal += itemTotal;
                    }
                    chargeAmount += orderTotal;
                    System.debug('submitPayment - Calculated from OrderItems: ' + orderTotal + ' (Order ID: ' + o.Id + ')');
                } else {
                    System.debug('submitPayment - Warning: Order ' + o.Id + ' has no TotalAmount and no OrderItems');
                }
            }
            
            System.debug('submitPayment - Final charge amount: ' + chargeAmount);
            
            // Process payment via Authorize.Net
            AuthorizeDotNet auth = new AuthorizeDotNet();
            auth.transaction(ccn,
                             month + year,
                             String.valueOf(chargeAmount),
                             cvn,
                             String.valueOf(0),
                             firstName,
                             lastName,
                             address,
                             city,
                             state,
                             postalCode);
            
            auth.process();
            PageReference pageRef = null;
            
            if (auth.isApproved()) {
                try {
                    // Check if we need to convert Lead to Account/Contact (for new registrations)
                    Id leadIdToConvert = null;
                    Id newMembershipAccountId = null;
                    
                    for (Order o : orders) {
                        if (o.Lead__c != null) {
                            leadIdToConvert = o.Lead__c;
                            break; // Use first Lead found
                        }
                    }
                    
                    // Get "New Membership Account" ID if we need to check
                    if (leadIdToConvert != null && accountIdToUse != null) {
                        try {
                            List<Account> tempAccounts = [SELECT Id FROM Account WHERE Name = 'New Membership Account' LIMIT 1];
                            if (!tempAccounts.isEmpty()) {
                                newMembershipAccountId = tempAccounts[0].Id;
                            }
                        } catch (Exception e) {
                            System.debug('Could not find New Membership Account: ' + e.getMessage());
                        }
                    }
                    
                    // Convert Lead to Account/Contact if Lead exists and accountIdToUse is null or points to "New Membership Account"
                    // NOTE: For new registrations, accountId parameter should already be set, so this conversion should not be needed
                    if (leadIdToConvert != null && (accountIdToUse == null || (newMembershipAccountId != null && accountIdToUse == newMembershipAccountId))) {
                        try {
                            Id convertedAccountId = convertLeadToAccountAndContact(leadIdToConvert);
                            if (convertedAccountId != null) {
                                accountIdToUse = convertedAccountId;
                                // Update orders to point to new account using helper class (without sharing)
                                for (Order o : orders) {
                                    o.AccountId = accountIdToUse;
                                }
                                // Use helper class to update orders without sharing restrictions
                                List<Database.SaveResult> updateResults = AccountUpdateHelper.updateOrders(orders);
                                // Check for errors
                                for (Database.SaveResult result : updateResults) {
                                    if (!result.isSuccess()) {
                                        System.debug('Error updating order: ' + result.getErrors());
                                    }
                                }
                                
                                // Create Terms and Conditions Acceptance after conversion
                                createTermsAcceptanceAfterConversion(accountIdToUse);
                            }
                        } catch (Exception conversionException) {
                            System.debug('Error converting Lead to Account/Contact: ' + conversionException.getMessage());
                            // Don't fail payment if conversion fails - log and continue
                        }
                    }
                    
                    // Verify user has access to the Account before processing orders
                    // userAccountId was already declared at the beginning of the method, reuse it
                    
                    // For renewals, ensure accountIdToUse matches user's AccountId
                    // If it doesn't match, use the AccountId from the Order (which should be the user's Account)
                    if (accountIdToUse != null && userAccountId != null && accountIdToUse != userAccountId) {
                        // Check if any order has a different AccountId that matches the user's AccountId
                        for (Order o : orders) {
                            if (o.AccountId == userAccountId) {
                                accountIdToUse = userAccountId;
                                System.debug('Using user AccountId from Order: ' + accountIdToUse);
                                break;
                            }
                        }
                    }
                    
                    // If accountIdToUse still doesn't match user's AccountId, use user's AccountId for renewals
                    if (accountIdToUse != null && userAccountId != null && accountIdToUse != userAccountId) {
                        // This is likely a renewal - use the user's AccountId
                        accountIdToUse = userAccountId;
                        System.debug('Using user AccountId for renewal: ' + accountIdToUse);
                    }
                    
                    // Ensure all orders have the correct AccountId set
                    // This is critical for cross-reference entity access
                    Boolean ordersNeedUpdate = false;
                    for (Order o : orders) {
                        if (o.AccountId != accountIdToUse) {
                            o.AccountId = accountIdToUse;
                            ordersNeedUpdate = true;
                        }
                    }
                    
                    // Update orders to ensure AccountId is set correctly before processing
                    // Use helper class to update without sharing restrictions
                    if (ordersNeedUpdate && !orders.isEmpty()) {
                        List<Database.SaveResult> updateResults = AccountUpdateHelper.updateOrders(orders);
                        // Check for errors
                        Boolean hasUpdateErrors = false;
                        for (Database.SaveResult result : updateResults) {
                            if (!result.isSuccess()) {
                                hasUpdateErrors = true;
                                System.debug('Error updating order before processing: ' + result.getErrors());
                                for (Database.Error err : result.getErrors()) {
                                    System.debug('Order update error: ' + err.getMessage());
                                }
                            }
                        }
                        if (hasUpdateErrors) {
                            return new PaymentResponseWrapper(false, 'Error updating orders. Please contact support.', null);
                        }
                    }
                    
                    // Verify Account access one more time using helper class
                    // This uses 'without sharing' so it should work for guest users
                    try {
                        Account accountCheck = AccountUpdateHelper.getAccountById(accountId);
                        if (accountCheck == null) {
                            return new PaymentResponseWrapper(false, 'ERROR: Account not found with ID: ' + accountId + '. Please contact support.', null);
                        }
                        System.debug('Account verified exists (without sharing): ' + accountId + ', Name: ' + accountCheck.Name);
                    } catch (Exception accountCheckException) {
                        String accountErrorMsg = 'ERROR checking Account access: ' + accountCheckException.getMessage();
                        if (accountCheckException.getMessage() != null && accountCheckException.getMessage().contains('List has no rows')) {
                            accountErrorMsg = 'ERROR: Account with ID ' + accountId + ' does not exist. Please contact support.';
                        }
                        return new PaymentResponseWrapper(false, accountErrorMsg, null);
                    }
                    
                    // IMPORTANT: CommunityOrderProcessor likely uses 'with sharing' which restricts access for guest users
                    // Even though Account exists, CommunityOrderProcessor may not be able to see it due to sharing rules
                    // Since we're in 'without sharing' context, we can't test 'with sharing' here
                    // But we know the Account exists, so if CommunityOrderProcessor fails, it's a sharing issue
                    System.debug('Account ' + accountId + ' exists. If CommunityOrderProcessor fails, it may be due to sharing rules.');
                    
                    // Validate orders before processing
                    if (orders == null || orders.isEmpty()) {
                        return new PaymentResponseWrapper(false, 'ERROR: No orders to process. Please contact support.', null);
                    }
                    
                    // Validate transaction ID
                    if (String.isBlank(auth.getTransactionID())) {
                        return new PaymentResponseWrapper(false, 'ERROR: Payment transaction ID is missing. Please contact support.', null);
                    }
                    
                    // Log information before processing (for debugging)
                    System.debug('About to process orders:');
                    System.debug('  Account ID: ' + accountIdToUse);
                    System.debug('  Order Count: ' + orders.size());
                    System.debug('  Transaction ID: ' + auth.getTransactionID());
                    for (Order o : orders) {
                        System.debug('  Order ID: ' + o.Id + ', Status: ' + o.Status + ', AccountId: ' + o.AccountId);
                        if (o.OrderItems != null) {
                            for (OrderItem oi : o.OrderItems) {
                                System.debug('    OrderItem: ProductCode=' + oi.Product2?.ProductCode + ', PricebookEntryId=' + oi.PricebookEntryId);
                            }
                        }
                    }
                    
                    // Validate OrderItems exist and have required fields
                    for (Order o : orders) {
                        if (o.OrderItems == null || o.OrderItems.isEmpty()) {
                            return new PaymentResponseWrapper(false, 'ERROR: Order ' + o.Id + ' has no OrderItems. Cannot process payment. Please contact support.', null);
                        }
                        for (OrderItem oi : o.OrderItems) {
                            if (oi.PricebookEntryId == null) {
                                return new PaymentResponseWrapper(false, 'ERROR: OrderItem in Order ' + o.Id + ' is missing PricebookEntryId. Cannot process payment. Please contact support.', null);
                            }
                            if (oi.Product2Id == null) {
                                return new PaymentResponseWrapper(false, 'ERROR: OrderItem in Order ' + o.Id + ' is missing Product2Id. Cannot process payment. Please contact support.', null);
                            }
                        }
                    }
                    
                    // Validate that PricebookEntry records exist for all OrderItems
                    Set<Id> pricebookEntryIds = new Set<Id>();
                    Set<Id> product2Ids = new Set<Id>();
                    for (Order o : orders) {
                        for (OrderItem oi : o.OrderItems) {
                            if (oi.PricebookEntryId != null) {
                                pricebookEntryIds.add(oi.PricebookEntryId);
                            }
                            if (oi.Product2Id != null) {
                                product2Ids.add(oi.Product2Id);
                            }
                        }
                    }
                    
                    // Check if PricebookEntry records exist and are properly configured
                    if (!pricebookEntryIds.isEmpty()) {
                        List<PricebookEntry> pbeList = [
                            SELECT Id, IsActive, Product2Id, Product2.ProductCode, 
                                   Pricebook2Id, Pricebook2.Name, UnitPrice
                            FROM PricebookEntry 
                            WHERE Id IN :pricebookEntryIds
                        ];
                        
                        if (pbeList.size() != pricebookEntryIds.size()) {
                            Set<Id> foundIds = new Set<Id>();
                            for (PricebookEntry pbe : pbeList) {
                                foundIds.add(pbe.Id);
                            }
                            Set<Id> missingIds = new Set<Id>();
                            for (Id pbeId : pricebookEntryIds) {
                                if (!foundIds.contains(pbeId)) {
                                    missingIds.add(pbeId);
                                }
                            }
                            return new PaymentResponseWrapper(false, 'ERROR: PricebookEntry records are missing: ' + missingIds + '. This is likely causing the "List has no rows" error in CommunityOrderProcessor. Please ensure all PricebookEntry records exist. Please contact support.', null);
                        }
                        
                        // Validate PricebookEntry records are active and properly configured
                        for (PricebookEntry pbe : pbeList) {
                            if (!pbe.IsActive) {
                                return new PaymentResponseWrapper(false, 'ERROR: PricebookEntry ' + pbe.Id + ' for Product ' + pbe.Product2?.ProductCode + ' is not active. This may cause issues in CommunityOrderProcessor. Please activate the PricebookEntry. Please contact support.', null);
                            }
                            if (pbe.Product2Id == null) {
                                return new PaymentResponseWrapper(false, 'ERROR: PricebookEntry ' + pbe.Id + ' is missing Product2Id. This is likely causing the "List has no rows" error in CommunityOrderProcessor. Please contact support.', null);
                            }
                            if (pbe.Pricebook2Id == null) {
                                return new PaymentResponseWrapper(false, 'ERROR: PricebookEntry ' + pbe.Id + ' is missing Pricebook2Id. This is likely causing the "List has no rows" error in CommunityOrderProcessor. Please contact support.', null);
                            }
                            System.debug('PricebookEntry validated: Id=' + pbe.Id + ', IsActive=' + pbe.IsActive + ', ProductCode=' + pbe.Product2?.ProductCode + ', Pricebook=' + pbe.Pricebook2?.Name);
                        }
                    }
                    
                    // Check if Product2 records exist and are active
                    if (!product2Ids.isEmpty()) {
                        List<Product2> productList = [
                            SELECT Id, Name, ProductCode, IsActive 
                            FROM Product2 
                            WHERE Id IN :product2Ids
                        ];
                        
                        if (productList.size() != product2Ids.size()) {
                            Set<Id> foundIds = new Set<Id>();
                            for (Product2 prod : productList) {
                                foundIds.add(prod.Id);
                            }
                            Set<Id> missingIds = new Set<Id>();
                            for (Id prodId : product2Ids) {
                                if (!foundIds.contains(prodId)) {
                                    missingIds.add(prodId);
                                }
                            }
                            return new PaymentResponseWrapper(false, 'ERROR: Product2 records are missing: ' + missingIds + '. This is likely causing the "List has no rows" error in CommunityOrderProcessor. Please ensure all Product2 records exist. Please contact support.', null);
                        }
                        
                        // Validate Product2 records are active
                        for (Product2 prod : productList) {
                            if (!prod.IsActive) {
                                return new PaymentResponseWrapper(false, 'ERROR: Product2 ' + prod.Id + ' (' + prod.ProductCode + ') is not active. This may cause issues in CommunityOrderProcessor. Please activate the Product. Please contact support.', null);
                            }
                            System.debug('Product2 validated: Id=' + prod.Id + ', ProductCode=' + prod.ProductCode + ', IsActive=' + prod.IsActive);
                        }
                    }
                    
                    // Additional validation: Check if Order has Pricebook2Id set
                    for (Order o : orders) {
                        if (o.Pricebook2Id == null) {
                            return new PaymentResponseWrapper(false, 'ERROR: Order ' + o.Id + ' is missing Pricebook2Id. CommunityOrderProcessor may require this. Please ensure the Order has a Pricebook2Id set. Please contact support.', null);
                        }
                        System.debug('Order validated: Id=' + o.Id + ', Pricebook2Id=' + o.Pricebook2Id + ', AccountId=' + o.AccountId);
                        
                        // Check OrderItems for Membership references
                        if (o.OrderItems != null) {
                            for (OrderItem oi : o.OrderItems) {
                                if (oi.Membership__c != null) {
                                    // Validate Membership record exists
                                    try {
                                        List<Membership__c> membershipList = [SELECT Id FROM Membership__c WHERE Id = :oi.Membership__c LIMIT 1];
                                        if (membershipList.isEmpty()) {
                                            return new PaymentResponseWrapper(false, 'ERROR: OrderItem references Membership ' + oi.Membership__c + ' which does not exist. This may cause "List has no rows" error in CommunityOrderProcessor. Please contact support.', null);
                                        }
                                        System.debug('Membership validated: Id=' + oi.Membership__c);
                                    } catch (Exception membershipException) {
                                        return new PaymentResponseWrapper(false, 'ERROR: Cannot validate Membership record ' + oi.Membership__c + ' for OrderItem. Error: ' + membershipException.getMessage() + '. Please contact support.', null);
                                    }
                                }
                            }
                        }
                    }
                    
                    System.debug('All validations passed. About to call CommunityOrderProcessor.processOrders...');
                    
                    // Use helper class to process orders without sharing restrictions
                    // This bypasses sharing rules while maintaining security (we've verified user access above)
                    // Note: If CommunityOrderProcessor has 'with sharing', this may still fail
                    // In that case, CommunityOrderProcessor would need to be modified
                    try {
                        System.debug('Calling AccountUpdateHelper.processOrdersWithoutSharing...');
                        System.debug('  AccountId (preserved from registration): ' + accountId);
                        System.debug('  ContactId (preserved from registration): ' + contactId);
                        System.debug('  Orders count: ' + orders.size());
                        System.debug('  Transaction ID: ' + auth.getTransactionID());
                        
                        // Use preserved AccountId and ContactId from registration (user requested: don't query, preserve from registration)
                        // accountIdToUse was already determined above (uses parameter accountId for new registrations, or userAccountId for renewals)
                        pageRef = AccountUpdateHelper.processOrdersWithoutSharing(accountIdToUse, contactId, orders, auth.getTransactionID());
                        
                        System.debug('CommunityOrderProcessor.processOrders completed successfully. PageRef: ' + (pageRef != null ? pageRef.getUrl() : 'null'));
                        
                        // Call async method to create Membership and User after payment completes
                        // This runs in a separate transaction to avoid callout/transaction issues
                        System.debug('===== QUEUEING MEMBERSHIP AND USER CREATION =====');
                        System.debug('  accountIdToUse: ' + accountIdToUse);
                        System.debug('  contactId: ' + contactId);
                        System.debug('  Orders count: ' + orders.size());
                        
                        for (Order o : orders) {
                            System.debug('  Checking Order: ' + o.Id);
                            System.debug('    Order.Lead__c: ' + o.Lead__c);
                            System.debug('    Order.AccountId: ' + o.AccountId);
                            System.debug('    OrderItems count: ' + (o.OrderItems != null ? o.OrderItems.size() : 0));
                            
                            if (o.OrderItems != null && !o.OrderItems.isEmpty()) {
                                for (OrderItem oi : o.OrderItems) {
                                    System.debug('    Checking OrderItem: ' + oi.Id);
                                    System.debug('      ProductCode: ' + (oi.Product2 != null ? oi.Product2.ProductCode : 'null'));
                                    
                                    // Check if this is a new membership registration (has Lead__c)
                                    // Also check if contactId is provided (for new registrations)
                                    if (accountIdToUse != null && contactId != null) {
                                        System.debug('✅✅✅ QUEUEING Membership and User creation ✅✅✅');
                                        System.debug('  OrderItem ID: ' + oi.Id);
                                        System.debug('  AccountId: ' + accountIdToUse);
                                        System.debug('  ContactId: ' + contactId);
                                        System.debug('  Order.Lead__c: ' + o.Lead__c);
                                        
                                        try {
                                            CommunityOrderProcessor.createMembershipAndUserAfterPayment(oi.Id, accountIdToUse, contactId);
                                            System.debug('✅✅✅ Successfully queued Membership and User creation ✅✅✅');
                                        } catch (Exception asyncEx) {
                                            System.debug('❌❌❌ ERROR queueing Membership/User creation: ' + asyncEx.getMessage());
                                            System.debug('❌ Stack trace: ' + asyncEx.getStackTraceString());
                                            // Don't fail payment - this is secondary
                                        }
                                        break; // Only process first OrderItem for new membership
                                    } else {
                                        System.debug('⚠️ Skipping - Missing required values:');
                                        System.debug('  accountIdToUse: ' + accountIdToUse);
                                        System.debug('  contactId: ' + contactId);
                                    }
                                }
                            }
                        }
                        System.debug('===== END QUEUEING =====');
                    } catch (QueryException qe) {
                        // QueryException specifically indicates "List has no rows"
                        String queryErrorMsg = qe.getMessage();
                        String queryStackTrace = qe.getStackTraceString();
                        
                        // Try to identify which record type is missing from stack trace
                        String missingRecord = 'unknown record';
                        if (String.isNotBlank(queryStackTrace)) {
                            if (queryStackTrace.contains('Membership__c') || queryStackTrace.contains('Membership')) {
                                missingRecord = 'Membership__c record';
                            } else if (queryStackTrace.contains('User')) {
                                missingRecord = 'User record';
                            } else if (queryStackTrace.contains('Account')) {
                                missingRecord = 'Account record';
                                // Account exists (we verified it), so this is likely a sharing issue
                                // Add note about sharing rules
                            } else if (queryStackTrace.contains('PricebookEntry')) {
                                missingRecord = 'PricebookEntry record';
                            } else if (queryStackTrace.contains('Product2')) {
                                missingRecord = 'Product2 record';
                            } else if (queryStackTrace.contains('Order')) {
                                missingRecord = 'Order record';
                            } else if (queryStackTrace.contains('OrderItem')) {
                                missingRecord = 'OrderItem record';
                            } else if (queryStackTrace.contains('Contact')) {
                                missingRecord = 'Contact record';
                            }
                        }
                        
                        String contextInfo = 'Account ID: ' + accountIdToUse + ', Order IDs: ' + (orderIds != null && !orderIds.isEmpty() ? String.join(orderIds, ', ') : 'none') + ', Transaction ID: ' + auth.getTransactionID();
                        
                        // Special handling for Account records - we know it exists, so it's likely a sharing issue
                        String sharingNote = '';
                        if (missingRecord == 'Account record') {
                            sharingNote = ' IMPORTANT: The Account exists (we verified it), but CommunityOrderProcessor cannot access it. This is likely because CommunityOrderProcessor uses "with sharing" which respects sharing rules. Guest users may not have access to this Account due to Account sharing settings. SOLUTION: Check Account sharing settings to grant access to guest users, or modify CommunityOrderProcessor class to use "without sharing".';
                        }
                        
                        String detailedError = 'ERROR: CommunityOrderProcessor failed - ' + missingRecord + ' not found (QueryException). This means CommunityOrderProcessor is trying to query for a ' + missingRecord + ' but it does not exist or is not accessible.' + sharingNote + ' Error: ' + queryErrorMsg + '. ' + contextInfo + '. Please check that the ' + missingRecord + ' exists and is accessible, then try again. Please contact support if the issue persists.';
                        
                        System.debug('QueryException caught: ' + detailedError);
                        System.debug('Stack trace: ' + queryStackTrace);
                        
                        return new PaymentResponseWrapper(false, detailedError, null);
                    } catch (NullPointerException npe) {
                        String npeMsg = npe.getMessage();
                        String npeStackTrace = npe.getStackTraceString();
                        String contextInfo = 'Account ID: ' + accountIdToUse + ', Order IDs: ' + (orderIds != null && !orderIds.isEmpty() ? String.join(orderIds, ', ') : 'none') + ', Transaction ID: ' + auth.getTransactionID();
                        String detailedError = 'ERROR: NullPointerException in CommunityOrderProcessor. This usually means a required field or record is null. Stack trace location: ' + (npeStackTrace.length() > 300 ? npeStackTrace.substring(0, 300) + '...' : npeStackTrace) + '. ' + contextInfo + '. Please contact support.';
                        
                        System.debug('NullPointerException caught: ' + detailedError);
                        return new PaymentResponseWrapper(false, detailedError, null);
                    } catch (Exception processException) {
                        String processErrorMsg = processException.getMessage();
                        String processStackTrace = processException.getStackTraceString();
                        String processErrorType = processException.getTypeName();
                        
                        // Handle null error messages
                        if (String.isBlank(processErrorMsg)) {
                            processErrorMsg = 'Unknown error in CommunityOrderProcessor.processOrders';
                            // Try to extract information from stack trace
                            if (String.isNotBlank(processStackTrace)) {
                                if (processStackTrace.contains('List has no rows')) {
                                    processErrorMsg = 'Required record not found in CommunityOrderProcessor';
                                } else if (processStackTrace.contains('NullPointerException')) {
                                    processErrorMsg = 'Null pointer exception in CommunityOrderProcessor';
                                } else if (processStackTrace.contains('DmlException')) {
                                    processErrorMsg = 'Database error in CommunityOrderProcessor';
                                }
                            }
                            if (String.isNotBlank(processErrorType)) {
                                processErrorMsg += ' (Type: ' + processErrorType + ')';
                            }
                        }
                        
                        // Build detailed error message
                        String detailedProcessError = 'ERROR processing orders: ' + processErrorMsg;
                        
                        // Add context information
                        String contextInfo = 'Account ID: ' + accountIdToUse + ', Order IDs: ' + (orderIds != null && !orderIds.isEmpty() ? String.join(orderIds, ', ') : 'none') + ', Transaction ID: ' + auth.getTransactionID();
                        
                        if (processErrorMsg.contains('List has no rows')) {
                            // Try to identify which record from stack trace
                            String missingRecord = 'unknown record';
                            if (String.isNotBlank(processStackTrace)) {
                                if (processStackTrace.contains('Membership__c') || processStackTrace.contains('Membership')) {
                                    missingRecord = 'Membership__c record';
                                } else if (processStackTrace.contains('User')) {
                                    missingRecord = 'User record';
                                } else if (processStackTrace.contains('Account')) {
                                    missingRecord = 'Account record';
                                } else if (processStackTrace.contains('PricebookEntry')) {
                                    missingRecord = 'PricebookEntry record';
                                } else if (processStackTrace.contains('Product2')) {
                                    missingRecord = 'Product2 record';
                                }
                            }
                            detailedProcessError = 'ERROR: Order processing failed - ' + missingRecord + ' not found in CommunityOrderProcessor. Error: ' + processErrorMsg + '. ' + contextInfo + '. Please contact support.';
                        } else if (processErrorMsg.contains('Null pointer')) {
                            detailedProcessError = 'ERROR: Null pointer exception in CommunityOrderProcessor. This usually means a required field or record is missing. Error: ' + processErrorMsg + '. ' + contextInfo + '. Please contact support.';
                        } else if (processErrorMsg.contains('Database error') || processErrorMsg.contains('DmlException')) {
                            detailedProcessError = 'ERROR: Database error in CommunityOrderProcessor. This could be due to validation rules, required fields, or data issues. Error: ' + processErrorMsg + '. ' + contextInfo + '. Please contact support.';
                        } else {
                            // Add stack trace snippet for context
                            if (String.isNotBlank(processStackTrace) && processStackTrace.length() > 0) {
                                String stackSnippet = processStackTrace.length() > 200 ? processStackTrace.substring(0, 200) + '...' : processStackTrace;
                                detailedProcessError += '. Location: ' + stackSnippet + '. ' + contextInfo;
                            } else {
                                detailedProcessError += '. ' + contextInfo;
                            }
                        }
                        
                        System.debug('Exception caught in processOrders: ' + detailedProcessError);
                        System.debug('Stack trace: ' + processStackTrace);
                        
                        // Return error directly instead of throwing to ensure message is preserved
                        return new PaymentResponseWrapper(false, detailedProcessError, null);
                    }
                } catch (Exception e) {
                    String errorMessage = e.getMessage();
                    String stackTrace = e.getStackTraceString();
                    String errorType = e.getTypeName();
                    Integer lineNumber = e.getLineNumber();
                    
                    // Handle null error messages (common cause of "Script-thrown exception")
                    if (String.isBlank(errorMessage)) {
                        errorMessage = 'Unknown error occurred';
                        
                        // Check if it's an AuraHandledException with null message
                        if (e instanceof AuraHandledException) {
                            errorMessage = 'AuraHandledException with no message';
                        }
                        
                        // Try to extract information from stack trace
                        if (String.isNotBlank(stackTrace)) {
                            // Look for method names in stack trace to identify where error occurred
                            if (stackTrace.contains('convertLeadToAccountAndContact')) {
                                errorMessage = 'Error during Lead conversion';
                            } else if (stackTrace.contains('processOrders') || stackTrace.contains('CommunityOrderProcessor')) {
                                errorMessage = 'Error in CommunityOrderProcessor.processOrders';
                            } else if (stackTrace.contains('getAccountById')) {
                                errorMessage = 'Error retrieving Account';
                            } else if (stackTrace.contains('updateOrders')) {
                                errorMessage = 'Error updating Orders';
                            } else if (stackTrace.contains('List has no rows')) {
                                errorMessage = 'List has no rows for assignment to SObject';
                            } else if (stackTrace.contains('NullPointerException')) {
                                errorMessage = 'Null pointer exception';
                            } else {
                                // Extract first method name from stack trace
                                Integer methodStart = stackTrace.indexOf('Class.') + 6;
                                if (methodStart > 5 && methodStart < stackTrace.length()) {
                                    Integer methodEnd = stackTrace.indexOf(':', methodStart);
                                    if (methodEnd > methodStart) {
                                        String methodName = stackTrace.substring(methodStart, methodEnd);
                                        errorMessage = 'Error in method: ' + methodName;
                                    }
                                }
                            }
                        }
                        // Add error type if available
                        if (String.isNotBlank(errorType)) {
                            errorMessage += ' (Type: ' + errorType + ')';
                        }
                        // Add line number if available
                        if (lineNumber != null && lineNumber > 0) {
                            errorMessage += ' at line ' + lineNumber;
                        }
                    }
                    
                    // Log detailed error information to help debug
                    System.debug('========== PAYMENT PROCESSING ERROR ==========');
                    System.debug('Error Type: ' + errorType);
                    System.debug('Error Message: ' + errorMessage);
                    System.debug('Stack Trace: ' + stackTrace);
                    System.debug('Line Number: ' + lineNumber);
                    System.debug('==============================================');
                    
                    // Create a more detailed error message for the user
                    String detailedErrorMessage = 'Error processing order: ' + errorMessage;
                    
                    // Add specific context based on error type
                    if (errorMessage != null && errorMessage.contains('List has no rows')) {
                        // Try to identify which query failed based on stack trace
                        if (stackTrace.contains('convertLeadToAccountAndContact')) {
                            detailedErrorMessage = 'ERROR: Lead conversion failed - Lead record not found. Please contact support.';
                        } else if (stackTrace.contains('getAccountById')) {
                            detailedErrorMessage = 'ERROR: Account lookup failed - Account not found. Please contact support.';
                        } else if (stackTrace.contains('processOrders') || stackTrace.contains('CommunityOrderProcessor')) {
                            detailedErrorMessage = 'ERROR: Order processing failed - required record not found in CommunityOrderProcessor. Please contact support with Order ID: ' + (orderIds != null && !orderIds.isEmpty() ? String.valueOf(orderIds[0]) : 'unknown');
                        } else if (stackTrace.contains('RecordType')) {
                            detailedErrorMessage = 'ERROR: RecordType not found. Please contact system administrator.';
                        } else if (stackTrace.contains('Profile')) {
                            detailedErrorMessage = 'ERROR: Profile not found. Please contact system administrator.';
                        } else {
                            // Extract first 300 chars of stack trace for context
                            String stackTraceSnippet = stackTrace.length() > 300 ? stackTrace.substring(0, 300) + '...' : stackTrace;
                            detailedErrorMessage = 'ERROR: Required record not found. Error: ' + errorMessage + '. Location in code: ' + stackTraceSnippet + '. Please contact support with Order ID: ' + (orderIds != null && !orderIds.isEmpty() ? String.valueOf(orderIds[0]) : 'unknown');
                        }
                    }
                    
                    // Check if this is an email-related error (non-critical)
                    Boolean isEmailError = errorMessage != null && (
                        errorMessage.contains('SendEmail failed') || 
                        errorMessage.contains('INVALID_EMAIL_ADDRESS') ||
                        errorMessage.contains('email')
                    );
                    
                    // If it's an email error, log it but don't fail the transaction
                    // Check if orders were actually processed (status changed to Complete)
                    Boolean ordersProcessed = false;
                    try {
                        List<Order> updatedOrders = [SELECT Id, Status FROM Order WHERE Id IN :orderIds LIMIT 1];
                        if (!updatedOrders.isEmpty() && updatedOrders[0].Status != 'Draft') {
                            ordersProcessed = true;
                        }
                    } catch (Exception checkException) {
                        // If we can't check, assume orders weren't processed
                        System.debug('Could not check order status: ' + checkException.getMessage());
                    }
                    
                    // If it's an email error and orders were processed, treat as success
                    if (isEmailError && ordersProcessed) {
                        System.debug('Email error occurred but orders were processed successfully: ' + errorMessage);
                        // Build redirect URL if pageRef exists
                        String redirectUrl = null;
                        if (pageRef != null) {
                            redirectUrl = Site.getBaseUrl() + pageRef.getUrl().removeStart('/apex');
                        }
                        return new PaymentResponseWrapper(true, 
                                                        'Payment processed successfully. (Note: Error notification email could not be sent.)', 
                                                        redirectUrl);
                    }
                    
                    // For non-email errors or if orders weren't processed, void payment and return error
                    if (!isEmailError || !ordersProcessed) {
                        CommunityUtil.voidPayment(auth.getTransactionId());
                        Credit_Card_Error__c errorRecord = new Credit_Card_Error__c();
                        errorRecord.Error_Text__c = errorMessage + stackTrace;
                        insert errorRecord;
                    }
                    
                    System.debug('Exception Stacktrace for Community Order Processor: ' + stackTrace);
                    
                    // Send error email (only if email addresses are configured)
                    // Wrap in try-catch to ensure it never throws exceptions
                    try {
                        String errorLogEmails = System.label.Community_Provider_Error_Log_Emails;
                        if (String.isNotBlank(errorLogEmails)) {
                            List<String> sendTo = new List<String>();
                            // Split by semicolon and filter out empty/null values
                            for (String email : errorLogEmails.split(';')) {
                                String trimmedEmail = email.trim();
                                if (String.isNotBlank(trimmedEmail)) {
                                    sendTo.add(trimmedEmail);
                                }
                            }
                            
                            // Only send email if we have valid addresses
                            if (!sendTo.isEmpty() && !isEmailError) {
                                // Don't try to send email if the original error was email-related
                                Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
                                message.toAddresses = sendTo;
                                message.optOutPolicy = 'FILTER';
                                message.plainTextBody = 'FSMTB Error with following code: ' + errorMessage + '\n\nStack Trace: ' + stackTrace;
                                Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage>{message};
                                Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
                                
                                if (results != null && !results.isEmpty() && results[0].success) {
                                    System.debug('The email was sent successfully.');
                                } else if (results != null && !results.isEmpty() && !results[0].success) {
                                    System.debug('The email failed to send: ' + (results[0].errors != null && !results[0].errors.isEmpty() ? results[0].errors[0].message : 'Unknown error'));
                                }
                            } else {
                                System.debug('Skipping error email: ' + (isEmailError ? 'Original error was email-related' : 'No valid email addresses configured'));
                            }
                        } else {
                            System.debug('Community_Provider_Error_Log_Emails custom label is not configured.');
                        }
                    } catch (Exception emailException) {
                        // Don't fail the entire transaction if email sending fails
                        System.debug('Error sending error notification email (ignored): ' + emailException.getMessage());
                    }
                    
                    // Only return error if orders weren't actually processed
                    if (!ordersProcessed) {
                        return new PaymentResponseWrapper(false, detailedErrorMessage, null);
                    }
                }
            }
            
            // Build redirect URL - navigate to payment confirmation LWC page
            String redirectUrl = null;
            if (auth.isApproved()) {
                // Navigate to payment confirmation page - return URL that LWC can detect
                redirectUrl = '/ce-payment-confirmation';
            } else if (pageRef != null) {
                // Fallback to original pageRef if payment failed
                redirectUrl = Site.getBaseUrl() + pageRef.getUrl().removeStart('/apex');
            }
            
            PaymentResponseWrapper response = new PaymentResponseWrapper(auth.isApproved(), 
                                            auth.getResponseText(), 
                                            redirectUrl);
            
            // Add email status information for debugging (visible in browser console)
            // Check CommunityOrderProcessor for email status (this is the class that's actually called)
            // Always populate these fields, even if empty, so the LWC can log them
            try {
                // Access static variables from CommunityOrderProcessor
                // Always set these fields, even if empty, to ensure they're returned to LWC
                response.emailStatus = CommunityOrderProcessor.emailStatusMessage != null ? CommunityOrderProcessor.emailStatusMessage : '';
                response.userCreated = CommunityOrderProcessor.userCreatedId != null ? String.valueOf(CommunityOrderProcessor.userCreatedId) : '';
                response.emailAddress = CommunityOrderProcessor.emailSentTo != null ? CommunityOrderProcessor.emailSentTo : '';
                
                System.debug('===== EMAIL STATUS DEBUG =====');
                System.debug('Email Status Message (raw): ' + CommunityOrderProcessor.emailStatusMessage);
                System.debug('User Created ID (raw): ' + CommunityOrderProcessor.userCreatedId);
                System.debug('Email Sent To (raw): ' + CommunityOrderProcessor.emailSentTo);
                System.debug('Response Email Status: ' + response.emailStatus);
                System.debug('Response User Created: ' + response.userCreated);
                System.debug('Response Email Address: ' + response.emailAddress);
                System.debug('=============================');
            } catch (Exception e) {
                System.debug('Could not retrieve email status: ' + e.getMessage());
                System.debug('Stack trace: ' + e.getStackTraceString());
                // Set empty strings if retrieval fails
                response.emailStatus = '';
                response.userCreated = '';
                response.emailAddress = '';
            }
            
            return response;
            
        } catch (Exception e) {
            String errorMsg = e.getMessage();
            String stackTrace = e.getStackTraceString();
            String errorType = e.getTypeName();
            
            // Handle null error messages
            if (String.isBlank(errorMsg)) {
                errorMsg = 'Unknown error occurred';
                // Try to extract information from stack trace
                if (String.isNotBlank(stackTrace)) {
                    if (stackTrace.contains('convertLeadToAccountAndContact')) {
                        errorMsg = 'Error during Lead conversion';
                    } else if (stackTrace.contains('processOrders') || stackTrace.contains('CommunityOrderProcessor')) {
                        errorMsg = 'Error in CommunityOrderProcessor.processOrders';
                    } else if (stackTrace.contains('getAccountById')) {
                        errorMsg = 'Error retrieving Account';
                    } else if (stackTrace.contains('List has no rows')) {
                        errorMsg = 'Required record not found (List has no rows)';
                    } else {
                        // Extract method name from stack trace
                        Integer methodStart = stackTrace.indexOf('Class.') + 6;
                        if (methodStart > 5 && methodStart < stackTrace.length()) {
                            Integer methodEnd = stackTrace.indexOf(':', methodStart);
                            if (methodEnd > methodStart) {
                                String methodName = stackTrace.substring(methodStart, methodEnd);
                                errorMsg = 'Error in method: ' + methodName;
                            }
                        }
                    }
                }
                if (String.isNotBlank(errorType)) {
                    errorMsg += ' (Type: ' + errorType + ')';
                }
            }
            
            System.debug('Error in submitPayment: ' + stackTrace);
            System.debug('Error Type: ' + errorType);
            System.debug('Error Message: ' + errorMsg);
            
            // Provide more context
            String finalErrorMsg = 'Error processing payment: ' + errorMsg;
            if (String.isNotBlank(stackTrace) && stackTrace.length() > 0) {
                // Add first part of stack trace for context (first 200 chars)
                String stackSnippet = stackTrace.length() > 200 ? stackTrace.substring(0, 200) + '...' : stackTrace;
                finalErrorMsg += '. Location: ' + stackSnippet;
            }
            
            return new PaymentResponseWrapper(false, finalErrorMsg, null);
        }
    }
    
    /**
     * Convert Lead to Account and Contact after payment is completed
     * Uses data from Lead: Organization Information -> Account, Registry Account Owner -> Contact
     */
    private static Id convertLeadToAccountAndContact(Id leadId) {
        try {
            // Get Lead with all fields
            List<Lead> leads = [
                SELECT Id, Company, Website, Email, Street, City, StateCode, PostalCode, Phone, Fax,
                       CountryCode, FirstName, LastName, Portal_Admin_Username__c, Portal_Admin_Email__c,
                       Portal_Admin_Phone__c, Portal_Admin_Title__c
                FROM Lead 
                WHERE Id = :leadId 
                LIMIT 1
            ];
            
            if (leads.isEmpty()) {
                throw new AuraHandledException('Lead not found with ID: ' + leadId);
            }
            
            Lead lead = leads[0];
            
            // Get Record Types
            List<RecordType> accRTList = [SELECT Id FROM RecordType WHERE SObjectType='Account' AND DeveloperName='CE_Provider' LIMIT 1];
            List<RecordType> conRTList = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='CE_Provider_User' LIMIT 1];
            
            if (accRTList.isEmpty()) {
                throw new AuraHandledException('CE_Provider Account RecordType not found. Please contact system administrator.');
            }
            if (conRTList.isEmpty()) {
                throw new AuraHandledException('CE_Provider_User Contact RecordType not found. Please contact system administrator.');
            }
            
            RecordType accRT = accRTList[0];
            RecordType conRT = conRTList[0];
            
            // Get CE Provider Administrator profile for the portal user
            List<Profile> ceAdminProfileList = [
                SELECT Id 
                FROM Profile 
                WHERE Name = 'CE Provider Administrator'
                LIMIT 1
            ];
            
            if (ceAdminProfileList.isEmpty()) {
                throw new AuraHandledException('CE Provider Administrator Profile not found. Please contact system administrator.');
            }
            
            Profile ceAdminProfile = ceAdminProfileList[0];
            
            // Validate required fields
            if (String.isBlank(lead.Company)) {
                throw new AuraHandledException('Business Name (Company) is required to create Account');
            }
            if (String.isBlank(lead.LastName)) {
                throw new AuraHandledException('Last Name is required to create Contact');
            }
            
            // Check if account with same name exists
            List<Account> existingAccs = [SELECT Id FROM Account WHERE Name = :lead.Company LIMIT 1];
            if (!existingAccs.isEmpty()) {
                throw new AuraHandledException('The Provider Name already exists in our system. Please provide a new name or contact FSMTB at CE@fsmtb.org with questions.');
            }
            
            // Format website URL
            String websiteUrl = lead.Website;
            if (!String.isBlank(websiteUrl) && 
                !websiteUrl.startsWithIgnoreCase('http://') &&
                !websiteUrl.startsWithIgnoreCase('https://')) {
                websiteUrl = 'https://' + websiteUrl;
            }
            
            // Create Account from Organization Information
            Account acc = new Account(
                Name = lead.Company,
                RecordTypeId = accRT.Id,
                Phone = lead.Phone,
                Fax = lead.Fax,
                Website = websiteUrl,
                BillingStreet = lead.Street,
                BillingCity = lead.City,
                BillingStateCode = lead.StateCode,
                BillingPostalCode = lead.PostalCode,
                BillingCountryCode = lead.CountryCode != null ? lead.CountryCode : 'US',
                Email__c = lead.Email,
                // Start new providers in an "Unpaid" registration state;
                // triggers will later move them to Provisional/Registered
                Registration_Status__c = 'Unpaid'
            );
            insert acc;
            
            // Create Contact from Registry Account Owner
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
            insert con;

            // Create initial portal User for the Registry Account Owner
            if (lead.Portal_Admin_Username__c == null) {
                throw new AuraHandledException('Portal admin username is missing on the Lead. Cannot create portal user.');
            }
            if (lead.Portal_Admin_Email__c == null) {
                throw new AuraHandledException('Portal admin email is missing on the Lead. Cannot create portal user.');
            }

            String communityUsername = lead.Portal_Admin_Username__c;

            User portalUser = new User(
                Username = communityUsername,
                LastName = String.isNotBlank(lead.LastName) ? lead.LastName : 'Provider',
                FirstName = lead.FirstName,
                Email = lead.Portal_Admin_Email__c,
                Alias = (lead.FirstName != null && lead.FirstName.length() >= 2 
                         ? lead.FirstName.substring(0, 2) 
                         : 'ce') + 'adm',
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = ceAdminProfile.Id,
                ContactId = con.Id,
                IsActive = true
            );
            insert portalUser;

            // Set the Portal Account Owner on the Account to this first user
            acc.Portal_Account_Owner__c = portalUser.Id;
            // Optionally move Registration_Status__c to Provisional now that payment is complete
            acc.Registration_Status__c = 'Provisional';
            update acc;
            
            // Delete the Lead after successful conversion
            delete lead;
            
            System.debug('Lead converted to Account/Contact/User after payment. Account ID: ' + acc.Id);
            return acc.Id;
            
        } catch (Exception e) {
            System.debug('Error converting Lead to Account/Contact/User: ' + e.getMessage());
            throw new AuraHandledException('Error converting Lead to Account/Contact/User: ' + e.getMessage());
        }
    }
    
    /**
     * Create Terms and Conditions Acceptance after Lead conversion
     */
    private static void createTermsAcceptanceAfterConversion(Id accountId) {
        try {
            String siteName = Site.getMasterLabel();
            String normalizedSiteName = normalizeSiteNameForTerms(siteName);
            
            // Get the Terms and Conditions record
            List<Terms_and_Conditions__c> termsList = [
                SELECT Id, Site__c, Activation_Date__c
                FROM Terms_and_Conditions__c
                WHERE (Site__c = :normalizedSiteName OR Site__c = :siteName OR Site__c LIKE 'CE Registry%')
                AND Activated__c = true 
                AND Activation_Date__c <= TODAY
                ORDER BY Activation_Date__c DESC, LastModifiedDate DESC
                LIMIT 1
            ];
            
            if (termsList.isEmpty()) {
                System.debug('No active Terms and Conditions found for site: ' + siteName);
                return;
            }
            
            Terms_and_Conditions__c terms = termsList[0];
            
            // Create Terms and Conditions Acceptance
            Terms_and_Conditions_Acceptance__c acceptance = new Terms_and_Conditions_Acceptance__c(
                Account__c = accountId,
                Terms_Accepted_By__c = UserInfo.getUserId(),
                Terms_and_Conditions__c = terms.Id
            );
            
            insert acceptance;
            System.debug('Terms and Conditions Acceptance created after Lead conversion: ' + acceptance.Id);
            
        } catch (Exception e) {
            System.debug('Error creating Terms Acceptance after conversion: ' + e.getMessage());
            // Don't throw - this is not critical for payment processing
        }
    }
    
    /**
     * Normalize site name for Terms lookup
     */
    private static String normalizeSiteNameForTerms(String siteName) {
        if (String.isBlank(siteName)) {
            return 'CE Registry';
        }
        if (siteName.contains('CE Registry')) {
            return 'CE Registry';
        }
        if (siteName.contains('Massage License Verification')) {
            return 'Massage License Verification Center';
        }
        return siteName;
    }
}

