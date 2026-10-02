using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ParkingManagement.Helpers;
using ParkingManagement.Interfaces;

namespace ParkingManagement.Controllers.ParkingSpace
{
    [ApiController]
    [Route("api/SpaceAvailability")]
    [Authorize(Policy = ParkingPermissions.ParkingOperations)]
    public class SpaceAvailabilityController : Controller
    {
        private readonly ISpaceAvailability _availability;
        private readonly ILogger<SpaceAvailabilityController> _logger;

        public SpaceAvailabilityController(
            ISpaceAvailability availability,
            ILogger<SpaceAvailabilityController> logger)
        {
            _availability = availability;
            _logger = logger;
        }

        [HttpGet]
        public IActionResult GetAvailability()
        {
            try
            {
                var spaces = _availability.GetSpaces();

                Response.Headers["Cache-Control"] = "no-store";

                return Ok(new
                {
                    spaces,
                    counts = new
                    {
                        total = spaces.Count,
                        available = spaces.Count(
                            space => space.SpaceStatus == "AVAILABLE"),
                        occupied = spaces.Count(
                            space => space.SpaceStatus == "OCCUPIED"),
                        blocked = spaces.Count(
                            space => space.SpaceStatus == "BLOCKED")
                    },
                    fetchedAtUtc = DateTime.UtcNow
                });
            }
            catch (Exception exception)
            {
                _logger.LogError(
                    exception,
                    "Could not retrieve parking space availability.");

                return StatusCode(500, new
                {
                    message = "Parking availability is temporarily unavailable."
                });
            }
        }
    }
}
