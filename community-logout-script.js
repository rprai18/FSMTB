// Logout functionality for Community
(function() {
    // Wait for DOM to be ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initLogout);
    } else {
        initLogout();
    }

    function initLogout() {
        // Use MutationObserver to handle dynamically loaded elements
        const observer = new MutationObserver(function(mutations) {
            attachLogoutHandler();
        });

        // Start observing
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });

        // Initial attachment
        attachLogoutHandler();
    }

    function attachLogoutHandler() {
        // Find profile name element
        const profileName = document.querySelector('.forceCommunityThemeProfileMenu .profile-name');
        
        if (profileName && !profileName.dataset.logoutAttached) {
            profileName.dataset.logoutAttached = 'true';
            
            // Create logout link element
            const logoutLink = document.createElement('span');
            logoutLink.textContent = ' | Logout';
            logoutLink.style.color = '#528dca';
            logoutLink.style.cursor = 'pointer';
            logoutLink.style.marginLeft = '0.5rem';
            logoutLink.style.fontFamily = "'Schibsted Grotesk', Montserrat, sans-serif";
            logoutLink.className = 'custom-logout-link';
            
            // Add hover effect
            logoutLink.addEventListener('mouseenter', function() {
                this.style.color = '#316ead';
                this.style.textDecoration = 'underline';
            });
            
            logoutLink.addEventListener('mouseleave', function() {
                this.style.color = '#528dca';
                this.style.textDecoration = 'none';
            });
            
            // Add click handler for logout
            logoutLink.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                
                // Navigate to logout URL
                window.location.href = '/secur/logout.jsp';
            });
            
            // Insert logout link after profile name
            profileName.parentNode.insertBefore(logoutLink, profileName.nextSibling);
        }
    }
})();



