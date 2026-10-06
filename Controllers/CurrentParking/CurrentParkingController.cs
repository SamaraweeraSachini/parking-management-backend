using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ParkingManagement.Helpers;
using ParkingManagement.Interfaces;

namespace ParkingManagement.Controllers.CurrentParking
{
    [ApiController]
    [Route("api/CurrentParking")]
    [Authorize(Policy = ParkingPermissions.ParkingOperations)]
    public class CurrentParkingController : ControllerBase
    {
        private readonly ICurrentParking _currentParking;
        private readonly ILogger<CurrentParkingController> _logger;

        public CurrentParkingController(ICurrentParking currentParking, ILogger<CurrentParkingController> logger)
        {
            _currentParking = currentParking;
            _logger = logger;
        }

        [HttpGet]
        public IActionResult GetCurrentParking([FromQuery] string searchTerm = "")
        {
            if (searchTerm != null && searchTerm.Length > 200)
            {
                return BadRequest(new
                {
                    message = "Search must contain no more than 200 characters."
                });
            }

            try
            {
                Response.Headers["Cache-Control"] = "no-store";

                return Ok(_currentParking.GetCurrentParking(searchTerm));
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Could not load current parking.");

                return StatusCode(500, new
                {
                    message = "Could not load current parking. Please try again."
                });
            }
        }
    }
}