# CLIProxyAPI {#module-services-cliproxyapi}

[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) provides OpenAI-, Gemini-, and Anthropic-compatible APIs for supported AI CLI subscriptions.

Enable the service with:

```nix
{
  services.cliproxyapi.enable = true;
}
```

The service runs as the configured `cliproxyapi` user and stores its configuration and authentication data in `services.cliproxyapi.dataDir` (by default, `/var/lib/cliproxyapi`). The module supports a managed `configFile`, a configurable listening `port`, firewall access, and local, Git, PostgreSQL, or S3-backed storage.

## Authentication {#module-services-cliproxyapi-authentication}

CLIProxyAPI authentication tokens are stored in the service data directory. The service can expose its management API for browser-based OAuth login, or the login commands can be run as the service user.

### Management API {#module-services-cliproxyapi-authentication-management-api}

Set `services.cliproxyapi.managementPasswordFile` to provide the management API password. Then use the corresponding CLIProxyAPI management endpoint to start authentication for a supported provider.

### Command-line login {#module-services-cliproxyapi-authentication-cli}

Run the provider-specific login command as the service user so the resulting token is written to the managed data directory. On a headless host, use the application's option to print the OAuth URL instead of opening a browser.
