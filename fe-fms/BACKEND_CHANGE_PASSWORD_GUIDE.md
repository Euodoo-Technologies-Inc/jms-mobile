# Backend Guide: Change Password API Endpoint

This document describes the API contract the mobile app expects for the **Change Password** feature. Use this to implement the corresponding backend endpoint.

## Endpoint

```
POST {baseUrl}/change-password
```

## Authentication

The request is authenticated via an API key passed in the `X-API-Key` header. This key is issued at login and stored on the device. The backend must validate this key and identify the authenticated user from it.

## Request

### Headers

| Header         | Value              |
|----------------|--------------------|
| `X-API-Key`    | `<user-api-key>`   |
| `Content-Type` | `application/json` |
| `Accept`       | `application/json` |

### Body

```json
{
  "current_password": "string",
  "new_password": "string",
  "new_password_confirmation": "string"
}
```

| Field                        | Type   | Required | Rules                                   |
|------------------------------|--------|----------|-----------------------------------------|
| `current_password`           | string | yes      | Must match the user's existing password |
| `new_password`               | string | yes      | Minimum 8 characters                    |
| `new_password_confirmation`  | string | yes      | Must match `new_password`               |

## Responses

### Success — `200 OK`

```json
{
  "success": true,
  "message": "Password changed successfully"
}
```

### Validation Error — `422 Unprocessable Entity`

Returned when the input fails validation (e.g., passwords don't match, new password too short).

```json
{
  "success": false,
  "message": "The new password confirmation does not match."
}
```

### Authentication Error — `401 Unauthorized`

Returned when the current password is incorrect or the API key is invalid.

```json
{
  "success": false,
  "message": "Current password is incorrect"
}
```

## Implementation Notes

### Laravel Example

If using Laravel, this can be implemented as:

```php
Route::post('/change-password', function (Request $request) {
    // Resolve user from X-API-Key header
    $apiKey = $request->header('X-API-Key');
    $user = User::where('api_key', $apiKey)->first();

    if (!$user) {
        return response()->json([
            'success' => false,
            'message' => 'Invalid API key',
        ], 401);
    }

    $request->validate([
        'current_password' => 'required|string',
        'new_password' => 'required|string|min:8|confirmed',
        // 'confirmed' rule checks against new_password_confirmation
    ]);

    if (!Hash::check($request->current_password, $user->password)) {
        return response()->json([
            'success' => false,
            'message' => 'Current password is incorrect',
        ], 401);
    }

    $user->update([
        'password' => Hash::make($request->new_password),
    ]);

    return response()->json([
        'success' => true,
        'message' => 'Password changed successfully',
    ]);
});
```

### Key Points

1. **Authenticate via `X-API-Key` header** — same mechanism used by all other authenticated endpoints in this app.
2. **Verify current password** before allowing the change — use `Hash::check()` or equivalent.
3. **Return JSON** with `success` (boolean) and `message` (string) fields — the app reads the `message` field for both success and error cases.
4. **Use standard HTTP status codes**: `200` for success, `401` for bad credentials/API key, `422` for validation failures.
5. **Hash the new password** before storing (e.g., `bcrypt` via `Hash::make()`).
