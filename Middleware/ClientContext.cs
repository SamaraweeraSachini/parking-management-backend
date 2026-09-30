using System;
using Microsoft.AspNetCore.Http;

namespace ParkingManagement.Middleware
{
    public static class ClientContext
    {
        private const string ClientCodeKey = "ClientCode";

        private static IHttpContextAccessor _httpContextAccessor;

        public static void Initialize(
            IHttpContextAccessor httpContextAccessor)
        {
            _httpContextAccessor = httpContextAccessor;
        }

        public static string ClientCode
        {
            get
            {
                return _httpContextAccessor?
                    .HttpContext?
                    .Items[ClientCodeKey]?
                    .ToString();
            }
        }

        public static void SetClientCode(string clientCode)
        {
            if (_httpContextAccessor?.HttpContext == null)
            {
                throw new InvalidOperationException(
                    "HTTP context is not available.");
            }

            _httpContextAccessor.HttpContext.Items[ClientCodeKey] = clientCode;
        }
    }
}