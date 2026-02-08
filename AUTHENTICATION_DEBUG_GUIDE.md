# Authentication Debug Guide

## Current Status

Debug logging has been added to diagnose the "Not authenticated" errors when accessing music tracks. This guide explains what to look for in the logs.

## Authentication Flow

### 1. App Startup
```
main.dart → AuthWrapper.initState() → AuthService.initialize()
```

When the app starts:
1. `AuthWrapper` widget's `initState()` schedules `AuthService.initialize()`
2. `AuthService.initialize()` attempts to restore the JWT token from `SharedPreferences`
3. If a valid token and user data exist, they're restored and the token is set in `ApiService`
4. Once initialization completes, `AuthWrapper` decides whether to show `MainScreen` or `LoginScreen`

### 2. API Requests
```
HomeScreen → ApiService.getFolders() → getHeaders(authenticated: true)
```

When making authenticated API calls:
1. `ApiService.getHeaders(authenticated: true)` is called
2. If `_authToken` is not null, it's included as `Authorization: Bearer <token>`
3. If `_authToken` is null, a warning is logged

## Debug Log Markers

### Authentication Initialization
Look for these logs in order:
```
🔐 AuthService: Initializing...
🔐 AuthService: Found stored token: <first 20 chars>...
🔐 AuthService: Token set for user: <email>
```

OR if no token exists:
```
🔐 AuthService: Initializing...
⚠️ AuthService: No stored token found
```

### Login Process
When logging in, you should see:
```
🔐 AuthService: Saving auth data for user: <email>
🔐 AuthService: Token saved and set: <first 20 chars>...
```

### API Request Headers
When making API calls, you should see:
```
🔑 Using auth token: <first 20 chars>...
🌐 API Request: <URL>
```

OR if the token is missing:
```
⚠️ AUTH REQUIRED but token is NULL!
```

### Folder Loading
When loading folders, you should see:
```
📁 Loaded <N> folders
  - "<folder path>" (<N> tracks)
```

## Common Issues and Solutions

### Issue 1: No Token Found on Startup
**Symptoms:**
```
🔐 AuthService: Initializing...
⚠️ AuthService: No stored token found
```

**Solution:** You need to log in. The app should show the login screen automatically.

### Issue 2: Token Exists but Not Being Used
**Symptoms:**
```
🔐 AuthService: Found stored token: abc123...
🔐 AuthService: Token set for user: user@example.com
...
⚠️ AUTH REQUIRED but token is NULL!
```

**This indicates a bug** - the token was set in AuthService but ApiService doesn't have it. This shouldn't happen with the current code.

### Issue 3: Token Invalid/Expired
**Symptoms:**
```
🔑 Using auth token: abc123...
🌐 API Request: http://...
[Error response from server: "Not authenticated"]
```

**Solution:** The token exists and is being sent, but the server rejects it. Try logging out and logging back in to get a fresh token.

### Issue 4: Authentication Errors
**Symptoms:**
```
{"detail": "Not authenticated"}
```

**Possible causes:**
1. No token stored (need to log in)
2. Token expired (need to re-login)
3. Token format incorrect
4. Backend authentication issue

## Troubleshooting Steps

1. **Run the app and look for the startup logs**
   - Do you see "Found stored token" or "No stored token found"?

2. **If no token found, try logging in**
   - Look for "Saving auth data for user" and "Token saved and set" logs

3. **After login, try accessing folders**
   - Look for "Using auth token" followed by "API Request" logs
   - If you see "AUTH REQUIRED but token is NULL", there's a bug

4. **Check the server response**
   - If token is being sent but you get "Not authenticated", the token may be invalid/expired

## Next Steps

After adding this debug logging:
1. Run the app (either rebuild or hot restart)
2. Check the console output for the log markers above
3. Share the relevant logs to identify where in the flow the authentication is failing

The logs will clearly show:
- Whether a token exists in storage
- Whether the token is being loaded correctly
- Whether the token is being sent in API requests
- Whether the server is accepting the token
