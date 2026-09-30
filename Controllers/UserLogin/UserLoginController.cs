using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ParkingManagement.Helpers;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;

namespace ParkingManagement.Controllers.UserLogin
{
    [ApiController]
    [Route("api/[controller]")]
    public class UserLoginController : Controller
    {
        private readonly IUserLogin _userLogin;
        private readonly ILogger<UserLoginController> _logger;

        public UserLoginController(IUserLogin userLogin,ILogger<UserLoginController> logger)
        {
            _userLogin = userLogin;
            _logger = logger;
        }

        [AllowAnonymous]
        [HttpPost("Login")]
        public async Task<IActionResult> Login([FromBody] UserLoginRequestAPI requestAPI)
        {
            //if (string.IsNullOrWhiteSpace(requestAPI.p_clientCode))
            //{
            //    return BadRequest("Client code is required.");
            //}

            // Check that a request was supplied.
            if (requestAPI == null)
            {
                return BadRequest(new
                {
                    message = "Username and password are required."
                });
            }

            if (string.IsNullOrWhiteSpace(requestAPI.Username))
            {
                return BadRequest("Username is required.");
            }

            if (string.IsNullOrWhiteSpace(requestAPI.Password))
            {
                return BadRequest("Password is required.");
            }

            //Response loginResult =_userLogin.FindActiveUser(requestAPI.Username.Trim());

            //if (loginResult.StatusCode != 200 || loginResult.ResultSet == null)
            //{
            //    return Unauthorized(new
            //    {
            //        StatusCode = 401,
            //        Result = "Invalid username or password"
            //    });
            //}

            //var users = loginResult.ResultSet as List<UserLoginModel>;

            //if (users == null || users.Count == 0)
            //{
            //    return Unauthorized(new
            //    {
            //        StatusCode = 401,
            //        Result = "Invalid username or password"
            //    });
            //}

            //UserLoginModel user = users[0];

            // Validate lengths before looking up the user.
            string username = requestAPI.Username.Trim();

            // The 72-byte password limit assumes BCrypt hashing.
            if (username.Length > 100 || Encoding.UTF8.GetByteCount(requestAPI.Password) > 72)
            {
                return InvalidLogin();
            }

            //Handle database and authentication failures.
            try
            {
                // ORIGINAL:
                //var user = _userLogin.FindActiveUser(requestAPI.Username.Trim());

                var user = _userLogin.FindActiveUser(username);

                // ORIGINAL:
                //if (user == null)
                //{
                //    return Unauthorized(new
                //    {
                //        StatusCode = 401,
                //        Result = "Invalid username or password"
                //    });
                //}

                // NEW: Allow active Admin and Operator accounts.
                if (user == null || !user.ActiveStatus || (user.UserRole != "A" && user.UserRole != "O"))
                {
                    return InvalidLogin();
                }

                // Check locked
                //if (user.FLD_IS_LOCKED == "1")
                //{
                //    return Unauthorized(new
                //    {
                //        StatusCode = 401,
                //        Result = "Account is locked"
                //    });
                //}

                // ORIGINAL: Check active
                //if (!user.ActiveStatus)
                //{
                //    return Unauthorized(new
                //    {
                //        StatusCode = 401,
                //        Result = "Account is inactive"
                //    });
                //}

                // Verify password
                bool isValidPassword = PasswordHasher.VerifyPassword(requestAPI.Password, user.PasswordHash);

                // ORIGINAL:
                //if (!isValidPassword)
                //{
                //    return Unauthorized(new
                //    {
                //        StatusCode = 401,
                //        Result = "Invalid username or password"
                //    });
                //}

                if (!isValidPassword)
                {
                    return InvalidLogin();
                }

                // ORIGINAL: Generate AuthKey
                //string authKey = AuthKeyGenerator.GenerateAuthKey(
                //    user.UserID.ToString(),
                //    user.UserRole,
                //    user.Username,
                //    "PARKING");

                //string testDecrypt = EncryptionHelper.DecryptStringAES(authKey);

                // ORIGINAL:
                //return Ok(new
                //{
                //    StatusCode = 200,
                //    Result = "Login successful",
                //
                //    ResultSet = new
                //    {
                //        UserId = user.UserID,
                //        Username = user.Username,
                //        UserRole = user.UserRole,
                //        AuthKey = authKey
                //    }
                //});

                // Store the authenticated user's identity and role.
                var claims = new List<Claim>
                {
                    new Claim(ClaimTypes.NameIdentifier,user.UserID.ToString()),
                    new Claim(ClaimTypes.Name,user.Username),
                    new Claim(ClaimTypes.Role,user.UserRole),
                    new Claim("FirstName",user.FirstName),
                    new Claim("LastName",user.LastName)
                };

                var identity = new ClaimsIdentity(claims,CookieAuthenticationDefaults.AuthenticationScheme);

                // Issue the authentication cookie.
                await HttpContext.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme,
                    new ClaimsPrincipal(identity),
                    new AuthenticationProperties
                    {
                        IsPersistent = false
                    });

                return Ok(new
                {
                    userId = user.UserID,
                    username = user.Username,
                    firstName = user.FirstName,
                    lastName = user.LastName,
                    role = user.UserRole
                });
            }
            catch (Exception exception)
            {
                _logger.LogError(exception,"Parking login failed.");

                return StatusCode(500, new
                {
                    message = "Login is temporarily unavailable. Please try again."
                });
            }
        }

        //[HttpPost("AddUser")]
        //[Authentication(UserTypes = new[] { "Z", "P", "C", "T", "A", "AC", "Q", "AP", "PO" })]
        //public IActionResult AddUser([FromBody]UserLoginRequestAPI requestAPI)
        //{
        //
        //    if (string.IsNullOrWhiteSpace(requestAPI.Username))
        //    {
        //        return BadRequest("Username is required.");
        //    }
        //
        //    if (string.IsNullOrWhiteSpace(requestAPI.Password))
        //    {
        //        return BadRequest("Password is required.");
        //    }
        //
        //    if (string.IsNullOrWhiteSpace(requestAPI.p_userTypeCode))
        //    {
        //        return BadRequest("User type is required.");
        //    }
        //
        //    return Ok(_userLogin.AddUser(requestAPI));
        //}

        // NEW: Return the currently authenticated user.
        [Authorize]
        [HttpGet("Me")]
        public IActionResult Me()
        {
            return Ok(new
            {
                userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!),
                username = User.FindFirstValue(ClaimTypes.Name),
                firstName = User.FindFirstValue("FirstName"),
                lastName = User.FindFirstValue("LastName"),
                role = User.FindFirstValue(ClaimTypes.Role)
            });
        }

        // NEW: Endpoint for checking authenticated access.
        [Authorize]
        [HttpGet("Protected")]
        public IActionResult Protected()
        {
            return Ok(new
            {
                message = "You are authenticated."
            });
        }

        // NEW: Remove the authentication cookie.
        [Authorize]
        [HttpPost("Logout")]
        public async Task<IActionResult> Logout()
        {
            await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);

            return Ok(new
            {
                message = "Logged out successfully."
            });
        }

        // NEW: Consistent response for invalid login attempts.
        private IActionResult InvalidLogin()
        {
            return Unauthorized(new
            {
                message = "Invalid username or password."
            });
        }
    }
}