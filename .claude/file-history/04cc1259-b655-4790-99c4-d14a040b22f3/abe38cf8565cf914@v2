# Fix: CodexSite Local Development — SPA Pages Return 500 Errors

## Context

When running CodexSite locally from Visual Studio, Swagger works fine but navigating to any actual page returns **500 errors** for all frontend assets (`bundle.js`, `index.bundle.css`, favicons, etc.). Dev, Staging, and Prod environments are unaffected.

### Root Cause

The error log tells the full story:

```
The NPM script 'start' exited without indicating that the create-react-app server was listening for requests.
The error output was: npm warn Unknown project config "always-auth".
```

**What's happening step-by-step:**

1. CodexSite uses the **legacy `UseOnePortal`** middleware path (via `OnePortalService` base class)
2. In `OnePortalApplicationBuilderExtension.cs` line 214, when the environment is `DevMachine`, it calls:
   ```csharp
   spa.UseReactDevelopmentServer(npmScript: "start");
   ```
3. This launches `npm run start` in the `ClientApp/` directory to spin up the React dev server
4. The `UseReactDevelopmentServer` middleware (from `Microsoft.AspNetCore.SpaServices.Extensions` v3.1.0) waits for the dev server to print a specific message indicating it's listening
5. **But the npm process fails immediately** because of the `always-auth=true` setting in `.npmrc` — newer versions of npm emit a warning: `npm warn Unknown project config "always-auth"`, and the `prestart` script or the `start` script itself exits before the dev server ever starts
6. Since the dev server never starts, **every non-API request** (JS bundles, CSS, images, etc.) hits the SPA proxy, which throws a 500 error

**Why Swagger works:** Swagger is served by ASP.NET middleware (`UseSwagger`/`UseSwaggerUI`) earlier in the pipeline (lines 155-160), so it never reaches the broken SPA proxy.

**Why Dev/Staging/Prod work:** In deployed environments, the environment is NOT `DevMachine`, so `UseReactDevelopmentServer` is never called. Instead, the pre-built static files from `ClientApp/build/` are served directly via `UseSpaStaticFiles()`.

### The `always-auth` Issue

The `.npmrc` files (both root and `ClientApp/.npmrc`) contain:
```
always-auth=true
```

In **npm v9+** (bundled with Node.js 18+), `always-auth` was deprecated and removed as a recognized config option. Running any npm command triggers:
```
npm warn Unknown project config "always-auth"
```

The `UseReactDevelopmentServer` middleware from `Microsoft.AspNetCore.SpaServices.Extensions` v3.1.0 interprets **any stderr output** as a failure and kills the process before it can start listening.

## Recommended Fix

Remove `always-auth=true` from the CodexSite `.npmrc` file. This setting is no longer needed in modern npm — authentication is now handled per-registry using `_auth` or `_authToken` entries in `.npmrc` (which are typically injected by `vsts-npm-auth` or `npx artifacts-credprovider`).

### File to Modify

**`fleetServices/CodexSite/src/Service/ClientApp/.npmrc`**

Current contents:
```
registry=https://msasg.pkgs.visualstudio.com/_packaging/IndexServe/npm/registry
always-auth=true
```

Change to:
```
registry=https://msasg.pkgs.visualstudio.com/_packaging/IndexServe/npm/registry
```

### Additional Consideration

The **root `.npmrc`** (`C:\Projects\Oneportal\.npmrc`) also has `always-auth=true`. If npm is resolving config from the root file too, that may also need to be cleaned up. However, since the CodexSite `.npmrc` is closer to the `ClientApp/` working directory, it takes precedence — so removing it from the CodexSite-specific file should fix the immediate issue.

If other OnePortal services (Hub, IBSite, IsDevPortal) have the same local development issue, their `.npmrc` files would need the same fix.

## Verification

1. Remove `always-auth=true` from `fleetServices/CodexSite/src/Service/ClientApp/.npmrc`
2. Open the solution in Visual Studio and run the CodexSite project (F5)
3. Wait for the React dev server to start (you should see webpack compilation output in the console)
4. Navigate to `http://localhost:86` — the OnePortal pages should now load correctly
5. Verify Swagger still works at `http://localhost:86/swagger`

If the React dev server still fails after this change, the next diagnostic step would be to manually run `cd ClientApp && npm run start` from a terminal to see the actual error output.
