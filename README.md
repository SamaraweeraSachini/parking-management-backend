# ParkingManagement Vehicle API — migrated to .NET 10

## What changed and why

| Area | .NET Framework 4.6.1 | .NET 10 |
|---|---|---|
| Web layer | `System.Web.Mvc` / `System.Web.Http` attributes | `Microsoft.AspNetCore.Mvc`, `ControllerBase` + `[ApiController]` |
| Hosting | `Global.asax`, IIS-hosted, `Web.config` | Minimal hosting model in `Program.cs`, runs anywhere (Kestrel, IIS, containers, Linux) |
| SQL driver | `System.Data.SqlClient` (legacy, in maintenance mode) | `Microsoft.Data.SqlClient` (actively developed) |
| DB calls | Synchronous | Async (`ExecuteReaderAsync`, `ExecuteNonQueryAsync`, etc.) |
| SQL queries | **String concatenation** — `"WHERE vehicle_id = '" + vehicle.vehicleId + "'"` | **Parameterized** — `"WHERE vehicle_id = @vehicleId"` |
| Connection string | Hardcoded in `DBconnect.cs`, committed to source | Read from `appsettings.json` / environment / secret manager |
| Object lifetime | `new DBconnect()` per call | Registered in DI (`AddScoped<DbConnect>()`) |
| Logging | Static `ParkingManagement.Static.LogHandler` (not in your uploads) | `ILogger<T>` via DI |
| `JsonRequestBehavior.AllowGet` | Required in ASP.NET MVC to allow JSON on GET | Not needed — ASP.NET Core has no such restriction |
| Interface name | `Ivehicle` | `IVehicle` (standard C# naming) |

## The SQL injection issue (fixed)

The original `DAVehicle.cs` built every INSERT/UPDATE/SELECT by concatenating
`VehicleModel` field values directly into the SQL string, e.g.:

```csharp
"WHERE vehicle_id = '" + vehicle.vehicleId + "'"
```

Any apostrophe or SQL metacharacter in a field the client controls (vehicle
IDs, driver numbers, filter parameters, etc.) could break out of the string
literal and alter the query, or run arbitrary SQL. Every query in the
rewritten `DAVehicle.cs` now uses `SqlCommand` parameters (`@vehicleId`, etc.)
instead — this was the single most important thing to fix while touching this
file, not an optional style change.

## What I could NOT port (files not provided)

1. **The `[Authentication]` attribute's real logic.** Your controller referenced
   `[Authentication(UserTypes = new[] {"EN","A","E","S","D"})]`, but the
   attribute's implementation wasn't among the uploaded files. I created a
   placeholder in `Filters/AuthenticationAttribute.cs` implementing
   ASP.NET Core's `IAuthorizationFilter` with the same declarative shape, but
   the actual "how do we know the current user's type" logic needs to be
   filled in — share the original file and I'll port it exactly.
2. **`LogHandler`** (`ParkingManagement.Static.LogHandler.WriteToLog`) — replaced with
   the standard `ILogger<DAVehicle>`. If the original wrote to a specific file
   format/location your ops tooling depends on, let me know.

## Database connectivity ("could not open a connection to SQL Server")

If you see:

```
A network-related or instance-specific error occurred while establishing a
connection to SQL Server... (provider: Named Pipes Provider, error: 40 -
Could not open a connection to SQL Server)
```

This is **not an application bug** - the API is correctly reporting that it
cannot reach the SQL Server instance named in your connection string. Fixing
it means checking the SQL Server / network side, in this order:

1. Confirm the named instance service is actually running (SQL Server
   Configuration Manager, on the DB machine).
2. Confirm the **SQL Server Browser** service is running - required for
   named instances (`SERVER\INSTANCE`) to resolve.
3. Enable both **TCP/IP** and **Named Pipes** protocols for the instance,
   then restart the SQL Server service.
4. Confirm **"Allow remote connections to this server"** is checked
   (Server Properties -> Connections) if the API and SQL Server are on
   different machines.
5. Check Windows Firewall / any network firewall allows TCP 1433 and
   UDP 1434 between the two machines.
6. Test directly from the machine running the API:
   `sqlcmd -S SERVER\INSTANCE -U youruser -P yourpassword`.
   If this also fails, it confirms the issue is server/network-side.
7. If the API and SQL Server are on the **same machine**, try
   `Data Source=localhost\INSTANCE` or `Data Source=.\INSTANCE` instead of
   the machine's network name - this avoids some Browser-service resolution
   issues.

`DbConnect.cs` now sets a 5-second connect timeout and wraps connection
failures with a message naming the unreachable server, so this fails fast
with a clear cause instead of hanging or surfacing a generic driver message.

## Deploying to IIS

This project targets **net10.0**. The IIS server must have the matching
**ASP.NET Core 10.0 Hosting Bundle** installed (not just the .NET runtime) or
you will get IIS error `HTTP 500.19 / 0x8007000d`. Verify with:

```
dotnet --list-runtimes
```

You should see `Microsoft.AspNetCore.App 10.0.x` in the list. If it's
missing, download the Hosting Bundle from
https://dotnet.microsoft.com/en-us/download/dotnet/10.0 and restart IIS
(`net stop was /y && net start w3svc`) after installing.

Publish with:

```
dotnet publish -c Release -r win-x64 --self-contained false
```

and deploy only the contents of the resulting `publish` folder (do not deploy
`bin`/`obj` from a regular build - they're excluded from this zip and from
git via `.gitignore`).

## Before running

- Replace `REPLACE_ME` in `appsettings.json` with the real password, or
  better, use `dotnet user-secrets` locally and an environment
  variable / key vault in production — don't commit real credentials.
- Wire up real authentication (`app.UseAuthentication()` in `Program.cs` is
  currently commented out as a TODO) once you tell me what your login flow
  issues (JWT? cookie? Windows auth?).
- `Microsoft.Data.SqlClient` and `Swashbuckle.AspNetCore` package versions in
  the `.csproj` are current as of my knowledge — run `dotnet restore` and bump
  if newer versions are out.

## Live vehicle location over WebSocket

`GET /VehicleRegister/UpdateVehicleLocation` (REST) still works exactly as
before, but a vehicle sending frequent location pings no longer has to open a
new HTTP request for every point. It can instead open one WebSocket
connection and keep streaming small JSON messages down it "time to time":

```
wss://<host>/ws/vehicle-location?vehicleId=VH-001
```

`vehicleId` is required on connect (query string) so the server knows which
vehicle every message on this socket belongs to. Once connected, send a
message per location ping:

```json
{ "latitude": "6.9271", "longitude": "79.8612" }
```

The server:
1. **Saves the connection** — `Sockets/WebSocketConnectionManager.cs` registers
   every open socket (keyed by a generated connection id + the vehicle id) in
   an in-memory, thread-safe dictionary so it can be found or broadcast to later.
2. **Persists the update** — each incoming message is passed straight into the
   existing `IVehicle.UpdateVehicleLocation` repository method, i.e. the same
   SQL path the REST endpoint already used, so there's one source of truth for
   how a location gets written.
3. **Acknowledges** — sends `{ "ok": true, "statusCode": 200, "message": "..." }`
   (or `ok: false` with an error) back down the same socket.
4. **Broadcasts** — on a successful save, fans a
   `{ "type": "locationUpdate", "vehicleId": ..., "latitude": ..., "longitude": ... }`
   message out to every *other* open connection, so something like a live
   tracking dashboard watching multiple vehicles gets updates pushed to it in
   real time instead of polling.

New files:
- `Sockets/WebSocketConnectionManager.cs` — the connection registry (singleton).
- `Sockets/VehicleLocationSocketHandler.cs` — accepts the handshake, saves the
  connection, and runs the receive loop.
- `Program.cs` — added `app.UseWebSockets()` and mapped `/ws/vehicle-location`
  to the handler.

Notes / things to decide next:
- The endpoint currently has no auth check (matches the rest of the API right
  now — see the `[Authentication]` TODO above). Once real auth is wired in,
  the socket handshake should validate the caller the same way before
  accepting the connection.
- Connections are in-memory per server instance. If you ever run more than
  one instance behind a load balancer, a client's connection only exists on
  the instance it's attached to — broadcasting across instances would need a
  backplane (e.g. Redis pub/sub) at that point.
- Quick manual test with [websocat](https://github.com/vi/websocat):
  ```
  websocat "ws://localhost:5080/ws/vehicle-location?vehicleId=VH-001"
  { "latitude": "6.9271", "longitude": "79.8612" }
  ```

## Chat over WebSocket

Same pattern, separate endpoint: `Sockets/ChatConnectionManager.cs` +
`Sockets/ChatSocketHandler.cs`, mapped in `Program.cs` to `/ws/chat`.

```
wss://<host>/ws/chat?userId=driver-42&room=vehicle-VH-001
```

Both `userId` and `room` are required on connect. `room` groups connections -
e.g. one room per vehicle/job, so a dispatcher and a driver land in the same
room and only see each other's messages. Once connected, send:

```json
{ "message": "On my way, ETA 10 minutes" }
```

The server:
1. **Saves the connection** (same idea as the vehicle-location manager, but
   keyed by room too) in `ChatConnectionManager`.
2. **Acknowledges** the sender with `{ "ok": true }` (or `ok: false` + an
   error for a malformed/empty message).
3. **Broadcasts** the message to everyone else currently in the same room as
   `{ "type": "chatMessage", "userId": ..., "room": ..., "message": ..., "timestampUtc": ... }`.
4. Also broadcasts `userJoined` / `userLeft` events to the room when someone
   connects or disconnects.

Not yet done:
- **No persistence** - chat messages aren't written to the database, only
  relayed live. There's no `ChatMessages` table in the current schema; say
  the word and I'll add one plus a repository (same shape as `IVehicle` /
  `DAVehicle`) and have `ChatSocketHandler` save through it the way
  `VehicleLocationSocketHandler` saves through `IVehicle.UpdateVehicleLocation`.
- **No auth check** on connect, same caveat as the location socket.

Quick manual test, two terminals in the same room:
```
websocat "ws://localhost:5080/ws/chat?userId=driver-42&room=vehicle-VH-001"
websocat "ws://localhost:5080/ws/chat?userId=dispatcher-1&room=vehicle-VH-001"
```
Type a JSON message in either terminal and it shows up in the other.
