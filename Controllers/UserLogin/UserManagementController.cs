using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ParkingManagement.Helpers;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;

namespace ParkingManagement.Controllers.UserLogin
{
    [ApiController]
    [Route("api/Users")]
    [Authorize(Policy = ParkingPermissions.AdminOnly)]
    public class UserManagementController : ControllerBase
    {
        private readonly IUserManagement _users;
        private readonly ILogger<UserManagementController> _logger;

        public UserManagementController(
            IUserManagement users,
            ILogger<UserManagementController> logger)
        {
            _users = users;
            _logger = logger;
        }

        [HttpGet]
        public IActionResult GetUsers()
        {
            try
            {
                var users = _users.GetUsers();

                return Ok(users.Select(user => new
                {
                    userId = user.UserID,
                    firstName = user.FirstName,
                    lastName = user.LastName,
                    username = user.Username,
                    userRole = user.UserRole,
                    activeStatus = user.ActiveStatus
                }));
            }
            catch (Exception exception)
            {
                return ServerError(exception);
            }
        }

        [HttpPost]
        public IActionResult CreateUser(
            [FromBody] CreateUserRequestAPI request)
        {
            if (!TryGetActingUserId(out int actingUserId))
            {
                return Unauthorized();
            }

            if (Encoding.UTF8.GetByteCount(request.Password) > 72)
            {
                return BadRequest(new
                {
                    message = "Password must not exceed 72 UTF-8 bytes."
                });
            }

            try
            {
                string hash = PasswordHasher.HashPassword(request.Password);

                return ChangeResponse(
                    _users.CreateUser(request, hash, actingUserId));
            }
            catch (Exception exception)
            {
                return ServerError(exception);
            }
        }

        [HttpPut("{userId:int}")]
        public IActionResult UpdateUser(
            int userId,
            [FromBody] UpdateUserRequestAPI request)
        {
            if (!TryGetActingUserId(out int actingUserId))
            {
                return Unauthorized();
            }

            if (userId <= 0)
            {
                return BadRequest(new
                {
                    message = "Invalid user ID."
                });
            }

            if (userId == actingUserId &&
                request.UserRole != ParkingPermissions.AdminRole)
            {
                return Conflict(new
                {
                    message = "You cannot change your own Admin role."
                });
            }

            try
            {
                return ChangeResponse(
                    _users.UpdateUser(userId, request, actingUserId));
            }
            catch (Exception exception)
            {
                return ServerError(exception);
            }
        }

        [HttpPatch("{userId:int}/deactivate")]
        public IActionResult DeactivateUser(int userId)
        {
            if (!TryGetActingUserId(out int actingUserId))
            {
                return Unauthorized();
            }

            if (userId <= 0)
            {
                return BadRequest(new
                {
                    message = "Invalid user ID."
                });
            }

            if (userId == actingUserId)
            {
                return Conflict(new
                {
                    message = "You cannot deactivate your own account."
                });
            }

            try
            {
                return ChangeResponse(
                    _users.DeactivateUser(userId, actingUserId));
            }
            catch (Exception exception)
            {
                return ServerError(exception);
            }
        }

        private bool TryGetActingUserId(out int userId)
        {
            return int.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out userId);
        }

        private IActionResult ChangeResponse(UserManagementResult result)
        {
            return StatusCode(result.StatusCode, new
            {
                message = result.Message,
                userId = result.UserId
            });
        }

        private IActionResult ServerError(Exception exception)
        {
            _logger.LogError(
                exception,
                "Parking user management failed.");

            return StatusCode(500, new
            {
                message = "User management is temporarily unavailable."
            });
        }
    }
}