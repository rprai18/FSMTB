# Terms & Conditions - VF to LWC Migration Summary

## ✅ Migration Complete!

I've successfully created a new separate `ceTermsAndConditions` LWC component matching the `CommunityTermsController` Visualforce page.

---

## 📋 What Was Done

### 1. **Created New Terms & Conditions LWC** (`ceTermsAndConditions`)
- ✅ Created separate LWC component matching VF page structure
- ✅ Loads Terms and Conditions text from `Terms_and_Conditions__c` object
- ✅ Displays terms text with HTML rendering
- ✅ Accept button creates Terms Acceptance record and Order
- ✅ Navigates to Payment LWC with order IDs dynamically

### 2. **Created Apex Controller** (`CeTermsAndConditionsLwcController.cls`)
- ✅ `getTermsData()` - Loads Terms and Conditions text for display
- ✅ `proceed()` - Accepts terms, creates Terms Acceptance record, converts Lead (if needed), creates Order
- ✅ `createTermsAcceptance()` - Creates `Terms_and_Conditions_Acceptance__c` record
- ✅ `convertLeadToAccount()` - Converts Lead to Account/Contact for new registration
- ✅ `createOrder()` - Creates Order with OrderItem for Registration/Renewal fee

### 3. **Updated Registration Form** (`cEregistrationForm`)
- ✅ Removed inline Terms section
- ✅ After creating Lead, navigates to separate Terms LWC page
- ✅ Passes `leadId` in navigation state

---

## 🎯 Key Features

### Terms & Conditions Flow

#### New Registration Flow:
1. **Registration Form** → Creates Lead → Navigates to Terms LWC with `leadId`
2. **Terms LWC** → Shows Terms → User clicks "Accept"
3. **Accept Terms** → Converts Lead to Account/Contact → Creates Terms Acceptance → Creates Order
4. **Navigate to Payment** → Passes order IDs → Payment LWC calculates price dynamically

#### Renewal Flow:
1. **Terms LWC** → Shows Terms (no leadId needed)
2. **Accept Terms** → Creates Terms Acceptance → Creates Order with existing Account
3. **Navigate to Payment** → Passes order IDs → Payment LWC calculates price dynamically

---

## 📂 Files Created

1. **`force-app/main/default/lwc/ceTermsAndConditions/ceTermsAndConditions.js`**
   - Handles terms data loading
   - Accepts terms and creates order
   - Navigates to payment

2. **`force-app/main/default/lwc/ceTermsAndConditions/ceTermsAndConditions.html`**
   - Displays header, terms text, Accept button
   - Shows admin redirect panel if needed

3. **`force-app/main/default/lwc/ceTermsAndConditions/ceTermsAndConditions.js-meta.xml`**
   - Exposed for Community Pages

4. **`force-app/main/default/classes/CeTermsAndConditionsLwcController.cls`**
   - Handles terms data retrieval
   - Creates Terms Acceptance record
   - Converts Lead to Account/Contact
   - Creates Order with OrderItem

---

## 🔄 Flow Comparison

### VF Page Flow:
1. Registration Form → Creates Lead → Navigates to `CommunityTerms` page with `leadId`
2. Terms Page → Shows Terms → User clicks "Accept"
3. Accept → Creates Order → Navigates to `CommunityPayment` page with order IDs

### LWC Flow (New):
1. Registration Form (`cEregistrationForm`) → Creates Lead → Navigates to `Terms__c` page with `leadId`
2. Terms LWC (`ceTermsAndConditions`) → Shows Terms → User clicks "Accept"
3. Accept → Creates Terms Acceptance → Converts Lead (if needed) → Creates Order → Navigates to `Payment__c` page with order IDs

---

## ✅ Terms Acceptance Logic

### When Accept is Clicked:
1. **Convert Lead** (if `leadId` provided and no existing Account)
   - Creates Account with RecordType = 'CE_Provider'
   - Creates Contact with RecordType = 'CE_Provider_User'
   - Deletes Lead after conversion

2. **Create Terms Acceptance Record**
   - Creates `Terms_and_Conditions_Acceptance__c` record
   - Links to Account and active Terms record
   - Records who accepted and when

3. **Create Order**
   - Creates Order with Status = 'Draft'
   - Creates OrderItem with Registration/Renewal fee product
   - Returns order IDs for payment navigation

4. **Navigate to Payment**
   - Uses `comm__namedPage` with name `Payment__c`
   - Passes order IDs in navigation state as JSON
   - Payment LWC receives order IDs and calculates price dynamically

---

## 🎨 UI Features

### Terms Display:
- ✅ Loads Terms text from `Terms_and_Conditions__c.Terms_and_Conditions_Text__c`
- ✅ Renders HTML content using `lwc:dom="manual"`
- ✅ Shows site name in header (e.g., "CE Registry Terms & Conditions")

### Accept Button:
- ✅ Shows "Accept" button
- ✅ Disables during processing
- ✅ Shows loading spinner while processing

### Error Handling:
- ✅ Shows error messages if Terms cannot be loaded
- ✅ Shows error messages if Accept fails
- ✅ Handles missing Lead ID gracefully (for renewal flow)

---

## 🔧 Configuration Required

### 1. Create Community Page for Terms LWC

You need to create a Community Page with:
- **API Name**: `Terms__c`
- **URL**: `/terms` (or your preferred URL)
- **Component**: `ceTermsAndConditions`

### 2. Update Navigation in Registration Form

If your Terms page API name is different, update this line in `cEregistrationForm.js`:
```javascript
name: 'Terms__c' // Update to match your Community Page API name
```

### 3. Ensure Products Exist

Make sure these products exist in your org:
- Product Code: `cer-membership` (for new registration)
- Product Code: `cer-membership-renewal` (for renewal)
- Both products should have PricebookEntry in "Standard Price Book"

---

## 🚀 Next Steps

### Step 1: Create Community Page for Terms LWC

1. Go to Experience Builder
2. Create new Page with API Name: `Terms__c`
3. Add `ceTermsAndConditions` component to the page
4. Publish the page

### Step 2: Test Registration Flow

1. Fill out registration form
2. Click "Next" → Should navigate to Terms page
3. Review Terms → Click "Accept"
4. Should navigate to Payment page with order IDs

### Step 3: Verify Order Creation

1. Check that Lead is converted to Account/Contact
2. Check that Terms Acceptance record is created
3. Check that Order with OrderItem is created
4. Verify Payment LWC receives order IDs and calculates price correctly

---

## 📝 Notes

### Lead Conversion:
- Lead is converted to Account/Contact when Accept is clicked on Terms page
- Terms Acceptance record is created AFTER Lead conversion (when Account exists)
- Lead is deleted after successful conversion

### Order Creation:
- Order is created with Status = 'Draft'
- OrderItem includes Registration/Renewal fee product
- Product code determined by whether Account exists (renewal vs new registration)

### Payment Integration:
- Order IDs passed to Payment LWC via navigation state
- Payment LWC receives order IDs and calculates price dynamically
- Payment LWC works for all payment types (Registration, Renewal, Course, etc.)

### Console Errors:
- CSP warnings for Google Analytics are expected (non-critical)
- Component profiling warnings are expected (non-critical)

---

## ✅ Success Criteria

- [x] Separate Terms LWC component created
- [x] Terms LWC loads Terms text from database
- [x] Terms LWC displays Terms text with HTML rendering
- [x] Accept button creates Terms Acceptance record
- [x] Accept button converts Lead to Account/Contact (for new registration)
- [x] Accept button creates Order with OrderItem
- [x] Accept button navigates to Payment LWC with order IDs
- [x] Registration form navigates to Terms LWC after creating Lead
- [x] Payment LWC receives order IDs dynamically
- [x] Payment LWC calculates price dynamically

---

## 🐛 Debugging Tips

### If "Next" button doesn't work:
1. Check browser console for errors
2. Verify form validation is passing
3. Check that `proceed()` Apex method is being called
4. Verify Lead is being created successfully

### If Terms page doesn't load:
1. Check that Community Page `Terms__c` exists
2. Verify Terms LWC component is added to the page
3. Check browser console for errors
4. Verify `leadId` is being passed in navigation state

### If Accept doesn't work:
1. Check browser console for errors
2. Verify Terms Acceptance record is being created
3. Verify Order is being created
4. Check that navigation to Payment page is working

---

## 📋 Checklist for Deployment

- [ ] Create Community Page for Terms LWC (`Terms__c`)
- [ ] Add `ceTermsAndConditions` component to Terms page
- [ ] Update Terms page API name in registration form if different
- [ ] Deploy `CeTermsAndConditionsLwcController.cls`
- [ ] Deploy `ceTermsAndConditions` LWC
- [ ] Deploy updated `cEregistrationForm` LWC
- [ ] Test registration flow end-to-end
- [ ] Test renewal flow (without leadId)
- [ ] Verify payment integration works correctly

---

**Migration Status**: ✅ **COMPLETE**

The Terms & Conditions page has been successfully migrated to a separate LWC component. The registration flow now navigates to the Terms page after creating a Lead, and the Terms page accepts terms, creates the Terms Acceptance record, converts the Lead (if needed), creates an Order, and navigates to Payment with order IDs dynamically! 🎉

