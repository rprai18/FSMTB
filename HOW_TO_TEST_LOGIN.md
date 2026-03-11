# How to Test Login Functionality in Community LWC

## Important Note
The `Site.login()` method **only works for Community/Experience Cloud users**, not for Salesforce admin users or standard Salesforce users. Admin credentials will not work with this login component.

## Steps to Test Login

### Option 1: Use an Existing Community User

1. **Find an Existing Community User:**
   - Go to Setup → Users → Users
   - Look for users with Profile = "CE Provider Administrator" or other Community profiles
   - Note their Username and ensure they have a password set

2. **Test Login:**
   - Navigate to your Community login page
   - Enter the Community user's username
   - Enter their password
   - Click Login

### Option 2: Create a Test Community User

1. **Create a Contact:**
   - Go to Contacts
   - Create a new Contact with:
     - First Name: Test
     - Last Name: User
     - Email: testuser@example.com
     - Account: Link to an existing Account (or create one)
     - Record Type: CE_Provider_User (if applicable)

2. **Create a User from the Contact:**
   - Go to Setup → Users → Users
   - Click "New User"
   - Fill in:
     - First Name: Test
     - Last Name: User
     - Alias: testuser
     - Email: testuser@example.com
     - Username: testuser@ceprovider.fsmtb.org (or your community domain)
     - Profile: CE Provider Administrator (or appropriate Community profile)
     - Contact: Select the Contact created in step 1
   - Check "Generate new password and notify user immediately"
   - Save

3. **Add User to Community:**
   - Go to Setup → Digital Experiences → All Sites
   - Click on your Community (e.g., "CE Registry Portal")
   - Go to Administration → Members
   - Click "Add Members"
   - Select the user you created
   - Add them to the appropriate profile/public group
   - Save

4. **Set Password:**
   - Go to Setup → Users → Users
   - Find the user you created
   - Click "Reset Password"
   - Copy the password (or set a new one)
   - Note: You may need to use "Login As" to set the password

5. **Test Login:**
   - Navigate to your Community login page
   - Enter the username (e.g., testuser@ceprovider.fsmtb.org)
   - Enter the password
   - Click Login

### Option 3: Use "Login As" Feature

1. **Login As a Community User:**
   - Go to Setup → Users → Users
   - Find a Community user
   - Click the dropdown next to their name
   - Select "Login"
   - This will log you in as that user in the Community

2. **Test the Login Flow:**
   - Logout from the Community
   - Use the login page to test the login functionality

## Troubleshooting

### Common Issues:

1. **"Login failed" error:**
   - Ensure the user is a member of the Community
   - Check that the user's profile has access to the Community
   - Verify the username format (may need @ceprovider.fsmtb.org suffix)

2. **"Invalid username or password":**
   - Verify the password is correct
   - Check if the user account is active
   - Ensure the user is not locked out

3. **Navigation fails after login:**
   - Check that the "Home" page exists in your Community
   - Verify the page API name is "Home"
   - Check browser console for navigation errors

4. **Apex class not accessible:**
   - Go to Setup → Apex Classes
   - Find "CommunityLoginLwcController"
   - Click "Security"
   - Add the Community user's profile to the list

## Quick Test Script

You can also test the login functionality using the browser console:

```javascript
// In browser console on the login page
// This will help debug the login process
console.log('Testing login...');
```

## Notes

- Admin users cannot login through Community login pages
- Only Community/Experience Cloud users can use `Site.login()`
- The username format may vary (e.g., username@ceprovider.fsmtb.org)
- Make sure the Community is active and published

