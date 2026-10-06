using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Data.SqlClient;
using ParkingManagement;
using ParkingManagement.DataAccess;
using ParkingManagement.Database_Layer;
using ParkingManagement.Helpers;
using ParkingManagement.Interfaces;
using ParkingManagement.Interfaces.VehicleType;
using ParkingManagement.Middleware;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddHttpContextAccessor();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

//builder.Services.AddScoped<ISupplierDetails, DASupplierDetails>();
builder.Services.AddScoped<IUserLogin, DAUserLogin>();
builder.Services.AddScoped<IVehicleType, DAVehicleType>();
builder.Services.AddScoped<IUserManagement, DAUserManagement>();
builder.Services.AddScoped<ISpaceAvailability, DASpaceAvailability>();
builder.Services.AddScoped<IParkingRate, DAParkingRate>();
builder.Services.AddScoped<IVehicleEntry, DAVehicleEntry>();
builder.Services.AddScoped<ICurrentParking, DACurrentParking>();

//builder.Services.AddSwaggerGen(c =>
//{
//    c.AddSecurityDefinition("AuthKey", new Microsoft.OpenApi.Models.OpenApiSecurityScheme
//    {
//        Name = "auth-key",
//        Type = Microsoft.OpenApi.Models.SecuritySchemeType.ApiKey,
//        In = Microsoft.OpenApi.Models.ParameterLocation.Header,
//        Description = "Enter your Auth Key"
//    });

//    c.AddSecurityRequirement(new Microsoft.OpenApi.Models.OpenApiSecurityRequirement
//    {
//        {
//            new Microsoft.OpenApi.Models.OpenApiSecurityScheme
//            {
//                Reference = new Microsoft.OpenApi.Models.OpenApiReference
//                {
//                    Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme,
//                    Id = "AuthKey"
//                }
//            },
//            Array.Empty<string>()
//        }
//    });
//});


builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowReactApp", policy =>
    {
        policy
            .WithOrigins("http://localhost:5173")
            .AllowAnyMethod()
            .AllowAnyHeader()
			.AllowCredentials();
    });
});

builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
	.AddCookie(options =>
	{
		options.Cookie.Name = "ParkingManagement.Auth";
		options.Cookie.HttpOnly = true;
		options.Cookie.SameSite = SameSiteMode.Strict;

		options.Cookie.SecurePolicy =
			builder.Environment.IsDevelopment()
				? CookieSecurePolicy.SameAsRequest
				: CookieSecurePolicy.Always;

		options.ExpireTimeSpan = TimeSpan.FromHours(8);
		options.SlidingExpiration = true;

		options.Events.OnRedirectToLogin = context =>
		{
			context.Response.StatusCode = 401;
			return Task.CompletedTask;
		};

		options.Events.OnRedirectToAccessDenied = context =>
		{
			context.Response.StatusCode = 403;
			return Task.CompletedTask;
		};

		options.Events.OnValidatePrincipal = async context =>
		{
			string userIdText = context.Principal?
				.FindFirstValue(ClaimTypes.NameIdentifier);

			if (!int.TryParse(userIdText, out int userId))
			{
				context.RejectPrincipal();
				await context.HttpContext.SignOutAsync(
					CookieAuthenticationDefaults.AuthenticationScheme);
				return;
			}

			try
			{
				var users = context.HttpContext.RequestServices
					.GetRequiredService<IUserLogin>();

				var currentUser = users.FindActiveUserById(userId);

				string storedRole = context.Principal
					.FindFirstValue(ClaimTypes.Role);

                if (currentUser == null || currentUser.UserRole != storedRole)
                {
                    context.RejectPrincipal();

                    await context.HttpContext.SignOutAsync(
                        CookieAuthenticationDefaults.AuthenticationScheme);

                    return;
                }

                // Refresh identity details after an administrator edits them.
                if (context.Principal.FindFirstValue(ClaimTypes.Name) != currentUser.Username ||
                    context.Principal.FindFirstValue("FirstName") != currentUser.FirstName ||
                    context.Principal.FindFirstValue("LastName") != currentUser.LastName)
                {
                    var claims = new List<Claim>
					{
						new Claim(
							ClaimTypes.NameIdentifier,
							currentUser.UserID.ToString()),

						new Claim(ClaimTypes.Name, currentUser.Username),
						new Claim(ClaimTypes.Role, currentUser.UserRole),
						new Claim("FirstName", currentUser.FirstName),
						new Claim("LastName", currentUser.LastName)
					};

						context.ReplacePrincipal(new ClaimsPrincipal(
							new ClaimsIdentity(
								claims,
								CookieAuthenticationDefaults.AuthenticationScheme)));

						context.ShouldRenew = true;
					}
            }
			catch (Exception exception)
			{
				var logger = context.HttpContext.RequestServices
					.GetRequiredService<ILoggerFactory>()
					.CreateLogger("ParkingAuthentication");

				logger.LogError(exception, "Could not validate parking session");

				context.RejectPrincipal();
			}
		};
	});

	builder.Services.AddAuthorization(options =>
	{
		options.AddPolicy(
			ParkingPermissions.AdminOnly,
			policy => policy
				.RequireAuthenticatedUser()
				.RequireRole(ParkingPermissions.AdminRole));

		options.AddPolicy(
			ParkingPermissions.ParkingOperations,
			policy => policy
				.RequireAuthenticatedUser()
				.RequireRole(
					ParkingPermissions.AdminRole,
					ParkingPermissions.OperatorRole));

		// Controllers without explicit authorization metadata
		// are restricted to administrators by default.
		options.FallbackPolicy = new AuthorizationPolicyBuilder()
			.RequireAuthenticatedUser()
			.RequireRole(ParkingPermissions.AdminRole)
			.Build();
	});

var app = builder.Build();

if (args.Contains("--bootstrap-admin"))
{
	Console.Write("First name: ");
	string firstName = Console.ReadLine()?.Trim() ?? "";

	Console.Write("Last name: ");
	string lastName = Console.ReadLine()?.Trim() ?? "";

	Console.Write("Username: ");
	string username = Console.ReadLine()?.Trim() ?? "";

	Console.Write("Password: ");
	string password = ReadBootstrapPassword();

	if (string.IsNullOrWhiteSpace(firstName) ||
		string.IsNullOrWhiteSpace(lastName) ||
		string.IsNullOrWhiteSpace(username) ||
		firstName.Length > 100 ||
		lastName.Length > 100 ||
		username.Length > 100 ||
		password.Length < 12 ||
		Encoding.UTF8.GetByteCount(password) > 72)
	{
		throw new InvalidOperationException(
			"Names and username are required. Password must contain " +
			"at least 12 characters and no more than 72 UTF-8 bytes.");
	}

	using var scope = app.Services.CreateScope();

	var users = scope.ServiceProvider
		.GetRequiredService<IUserLogin>();

	int userId = users.CreateFirstAdmin(
		firstName,
		lastName,
		username,
		PasswordHasher.HashPassword(password));

	Console.WriteLine($"First Admin created. User ID: {userId}");
	return;
}

//test block to see if the database connected.
//if (app.Environment.IsDevelopment())
//{
//	using var database = new DBconnect("PARKING");
//	using var connection = database.GetOpenConnection();

//	Console.WriteLine(
//		$"Parking database connected: {connection.Database}");
//}

// TEMPORARY: shows full exception details in the browser response.
// Remove this once you've found and fixed the real error.

ClientContext.Initialize(app.Services.GetRequiredService<IHttpContextAccessor>());

if (app.Environment.IsDevelopment())
{
	app.UseDeveloperExceptionPage();
	app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseCors("AllowReactApp");
app.UseAuthentication();
app.UseAuthorization();

app.UseWebSockets(new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromSeconds(30)
});

app.MapControllers();
app.Run();

static string ReadBootstrapPassword()
{
	var characters = new List<char>();

	while (true)
	{
		var key = Console.ReadKey(intercept: true);

		if (key.Key == ConsoleKey.Enter)
			break;

		if (key.Key == ConsoleKey.Backspace)
		{
			if (characters.Count > 0)
				characters.RemoveAt(characters.Count - 1);

			continue;
		}

		if (!char.IsControl(key.KeyChar))
			characters.Add(key.KeyChar);
	}

	Console.WriteLine();
	return new string(characters.ToArray());
}