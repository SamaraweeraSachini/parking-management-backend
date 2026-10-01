using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ParkingManagement.Helpers;

namespace ParkingManagement.Controllers.UserLogin
{
    [ApiController]
    [Route("api/Permissions")]
    public class PermissionsController : Controller
    {
        [Authorize(Policy = ParkingPermissions.AdminOnly)]
        [HttpGet("Admin")]
        public IActionResult Admin()
        {
            return Ok(new
            {
                message = "Administrator access granted."
            });
        }

        [Authorize(Policy = ParkingPermissions.ParkingOperations)]
        [HttpGet("Operations")]
        public IActionResult Operations()
        {
            return Ok(new
            {
                message = "Parking operations access granted."
            });
        }
    }
}
