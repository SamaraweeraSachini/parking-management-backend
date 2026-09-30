using Microsoft.AspNetCore.Mvc.Filters;
using System;
using System.Linq;

namespace ParkingManagement.Filters
{
    // NOTE: your original [Authentication(UserTypes = new[] {"EN","A","E","S","D"})]
    // attribute was referenced by VehicleController.cs but its implementation was
    // not among the uploaded files, so I could not port its actual logic. This is
    // a placeholder that reproduces the same declarative shape
    // (Authorize -> Authentication) as an ASP.NET Core IAuthorizationFilter.
    //
    // TODO: replace the body of OnAuthorization with your real check - typically
    // reading the authenticated user's "type" claim (set at login) and confirming
    // it's one of UserTypes. Please share the original Authentication attribute
    // (and whatever sets the user's type on login) and I'll wire this up exactly.
    [AttributeUsage(AttributeTargets.Method | AttributeTargets.Class)]
    public class AuthenticationAttribute : Attribute, IAuthorizationFilter
    {
        public string[] UserTypes { get; set; } = Array.Empty<string>();

        public void OnAuthorization(AuthorizationFilterContext context)
        {
            var user = context.HttpContext.User;

            if (user?.Identity == null || !user.Identity.IsAuthenticated)
            {
                context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
                return;
            }

            // Placeholder claim type - adjust to match how your login flow issues claims.
            var userType = user.FindFirst("UserType")?.Value;

            if (UserTypes.Length > 0 && !UserTypes.Contains(userType))
            {
                context.Result = new Microsoft.AspNetCore.Mvc.ForbidResult();
            }
        }
    }
}
