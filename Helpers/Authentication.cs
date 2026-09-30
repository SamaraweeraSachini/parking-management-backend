using ParkingManagement.Helpers;
using ParkingManagement.Middleware;
using ParkingManagement.Static;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace ParkingManagement.Authentication
{
    public class AuthenticationAttribute : ActionFilterAttribute
    {
        public string[] UserTypes { get; set; }

        public override void OnActionExecuting( ActionExecutingContext context)
        {
            Authenticate(context);
        }

        private void Authenticate( ActionExecutingContext context)
        {
            var request = context.HttpContext.Request;
            if (!request.Headers.TryGetValue( "auth-key", out var authKey))
            {
                context.Result = new UnauthorizedObjectResult(
                    new
                    {
                        StatusCode = 401,
                        Result = "Auth key is required"
                    });

                return;
            }

            if (string.IsNullOrWhiteSpace(authKey))
            {
                context.Result = new UnauthorizedObjectResult(
                    new
                    {
                        StatusCode = 401,
                        Result = "Invalid auth key"
                    });

                return;
            }

            try
            {
                // Decrypt AuthKey
                string decrypted =  EncryptionHelper.DecryptStringAES(  authKey.ToString());

                if (string.IsNullOrWhiteSpace(decrypted))
                {
                    context.Result =  new UnauthorizedObjectResult(
                            new
                            {
                                StatusCode = 401,
                                Result = "Invalid auth key"
                            });

                    return;
                }

                // Expected:
                // UserId`UserType`Username`ClientCode
                string[] decryptKeys =  decrypted.Split('`');

                if (decryptKeys.Length != 4)
                {
                    context.Result = new UnauthorizedObjectResult(
                        new
                        {
                            StatusCode = 401,
                            Result = "Invalid auth key"
                        });

                    return;
                }

                string userId = decryptKeys[0];
                string userType = decryptKeys[1];
                string username = decryptKeys[2];
                string clientCode = decryptKeys[3];

                if (string.IsNullOrWhiteSpace(userId) || string.IsNullOrWhiteSpace(userType) || string.IsNullOrWhiteSpace(username) ||  string.IsNullOrWhiteSpace(clientCode))
                {
                    context.Result = new UnauthorizedObjectResult(
                            new
                            {
                                StatusCode = 401,
                                Result = "Invalid auth key"
                            });

                    return;
                }

                // Check allowed user type
                if (UserTypes != null &&  UserTypes.Length > 0)
                {
                    bool isAllowed = UserTypes.Contains(userType, StringComparer.OrdinalIgnoreCase);

                    if (!isAllowed)
                    {
                        context.Result =new ObjectResult(
                                new
                                {
                                    StatusCode = 403,
                                    Result = "User is not authorized"
                                })
                            {
                                StatusCode = 403
                            };

                        return;
                    }
                }

                // Store authentication information
                context.HttpContext.Items["UserId"] = userId;
                context.HttpContext.Items["UserType"] = userType;
                context.HttpContext.Items["Username"] = username;
                context.HttpContext.Items["ClientCode"] = clientCode;

                // Set ClientContext
                ClientContext.SetClientCode(clientCode);
            }
            catch (Exception ex)
            {
                LogHandler.WriteToLog( ex.Message, "Authentication failed", System.Reflection.MethodBase .GetCurrentMethod() .Name);

                context.Result =  new UnauthorizedObjectResult( new
                    {
                        StatusCode = 401,
                        Result = "Invalid auth key"
                    });

                return;
            }
        }
    }
}