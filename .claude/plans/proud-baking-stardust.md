# CodexUpdater Crash: Root Cause Analysis & Fix

## Context

After merge commit `c36c474` ("papyrusconfigservice to scoped"), CodexUpdater is crashing. The user wants to understand why and fix it.

**Key finding:** Commit `c36c474` only changed `CodexSite.cs` (not CodexUpdater). However, the underlying issue in CodexUpdater's DI registrations has existed since the `service-tree parents` commit (`74c2c77b`, March 2) and was made worse when `AppIdToProductResolver` was registered directly (`e9b267f9` / `b22fa0c5`, March 19-20). The crash may have been triggered by a deployment that included both the CodexSite scoped changes and the pre-existing CodexUpdater misconfiguration.

## Root Cause

**Two DI registration bugs in `fleetServices/CodexUpdater/src/Service/Startup.cs`:**

### Bug 1: Missing `IServiceTreeParentGroupCatalog` registration

`ServiceTreeParentResolver` requires three constructor dependencies:
```
ServiceTreeParentResolver(
    IServiceTreeNodeLookup nodeLookup,        // Registered as Singleton (line 129) ✓
    IServiceTreeParentGroupCatalog catalog,   // ❌ NOT REGISTERED AT ALL
    ILogger<ServiceTreeParentResolver> logger // Framework-provided ✓
)
```

`IServiceTreeParentGroupCatalog` / `ServiceTreeParentGroupCatalog` is **never registered** in CodexUpdater's `Startup.cs`. When the DI container tries to construct `ServiceTreeParentResolver`, it fails with:

> `InvalidOperationException: Unable to resolve service for type 'IServiceTreeParentGroupCatalog'`

This gets hit when `UtilizationMetricBackgroundService` creates a scope (line 57-58 of `UtilizationMetricBackgroundService.cs`) and resolves `UtilizationMetricCollector`, which depends on `IAppIdToProductResolver` → `IServiceTreeParentResolver`.

### Bug 2: Captive dependency — Singleton depends on Scoped

Even if Bug 1 is fixed, there's a lifetime mismatch:

| Service | Lifetime in CodexUpdater | Problem |
|---|---|---|
| `IServiceTreeParentResolver` | **Singleton** (line 130) | ❌ Will capture scoped deps |
| `IAppIdToProductResolver` | Scoped (line 131) | Depends on the Singleton above |
| `IPapyrusConfigService` | Scoped (line 100) | Depends on `IUnitOfCodeX` (Scoped) |

`AppIdToProductResolver` is Scoped and depends on both `IPapyrusConfigService` (Scoped) and `IServiceTreeParentResolver` (Singleton). While this direction is technically OK (Scoped can consume Singleton), the **real problem** is that `IServiceTreeParentResolver` is Singleton but `ServiceTreeParentResolver` could be used in ways that assume scoped lifetime.

More critically, `IServiceTreeParentResolver` should be Scoped to match CodexSite's pattern (which was fixed in commit `c36c474`). CodexSite correctly has it as Scoped. CodexUpdater was not updated alongside CodexSite.

### Crash Path

```
UtilizationMetricBackgroundService.ExecuteAsync()
  → serviceProvider.CreateScope()
  → scope.GetRequiredService<UtilizationMetricCollector>()
    → needs IAppIdToProductResolver (Scoped)
      → AppIdToProductResolver constructor needs:
        → IPapyrusConfigService (Scoped) ✓
        → IServiceTreeParentResolver (Singleton)
          → ServiceTreeParentResolver constructor needs:
            → IServiceTreeNodeLookup (Singleton) ✓
            → IServiceTreeParentGroupCatalog ❌ NOT REGISTERED → CRASH
            → ILogger ✓
```

## Fix — File: `fleetServices/CodexUpdater/src/Service/Startup.cs`

### Change 1: Add missing `IServiceTreeParentGroupCatalog` registration (add after line 129)

```csharp
services.AddSingleton<IServiceTreeParentGroupCatalog, ServiceTreeParentGroupCatalog>();
```

This is appropriate as Singleton because `ServiceTreeParentGroupCatalog` only depends on `IGitClient` (Singleton) and `ILogger` (framework). It has its own internal caching (`CachedCatalog`) that makes Singleton ideal.

### Change 2: Change `IServiceTreeParentResolver` from Singleton to Scoped (line 130)

```csharp
// Before:
services.AddSingleton<IServiceTreeParentResolver, ServiceTreeParentResolver>();
// After:
services.AddScoped<IServiceTreeParentResolver, ServiceTreeParentResolver>();
```

This matches CodexSite's registration (line 109 of `CodexSite.cs`) and ensures consistency across services. While `ServiceTreeParentResolver` itself only depends on Singleton/framework services, making it Scoped is the correct pattern to match CodexSite and avoid future captive dependency issues.

### Required import (add to usings at top of file)

The file already imports `CodeXCore.ServiceTree` (which contains `ServiceTreeParentResolver`, `IServiceTreeParentResolver`). The `IServiceTreeParentGroupCatalog` and `ServiceTreeParentGroupCatalog` are also in the `CodeXCore.ServiceTree` namespace, so no new using statement is needed.

## Files to Modify

1. **`fleetServices/CodexUpdater/src/Service/Startup.cs`** — Add `IServiceTreeParentGroupCatalog` registration and change `IServiceTreeParentResolver` to Scoped

## Verification

1. **Build:** `dotnet build fleetServices/CodexUpdater/src/Service/Codex.Updater.csproj` — should compile without errors
2. **Runtime check:** The `UtilizationMetricBackgroundService` should no longer crash when resolving `UtilizationMetricCollector` → `AppIdToProductResolver` → `ServiceTreeParentResolver`
3. **Cross-check with CodexSite:** Verify the registration lifetimes now match between CodexUpdater and CodexSite for all shared services
