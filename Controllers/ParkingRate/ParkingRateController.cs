using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ParkingManagement.Helpers;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;

namespace ParkingManagement.Controllers.ParkingRate
{
    [ApiController]
    [Route("api/Rates")]
    [Authorize]
    public class ParkingRateController : ControllerBase
    {
        private readonly IParkingRate _parkingRate;
        private readonly ILogger<ParkingRateController> _logger;

        public ParkingRateController(IParkingRate parkingRate, ILogger<ParkingRateController> logger)
        {
            _parkingRate = parkingRate;
            _logger = logger;
        }

        [HttpGet]
        [Authorize(Policy = ParkingPermissions.AdminOnly)]
        public IActionResult GetRates()
        {
            try
            {
                Response.Headers["Cache-Control"] = "no-store";
                return Ok(_parkingRate.GetRates());
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Could not load parking rates.");
                return StatusCode(500, new
                {
                    message = "Could not load parking rates. Please try again."
                });
            }
        }

        [HttpGet("VehicleTypes")]
        [Authorize(Policy = ParkingPermissions.AdminOnly)]
        public IActionResult GetVehicleTypes()
        {
            try
            {
                Response.Headers["Cache-Control"] = "no-store";
                return Ok(_parkingRate.GetActiveVehicleTypes());
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Could not load vehicle types for parking rates.");

                return StatusCode(500, new
                {
                    message = "Could not load vehicle types. Please try again."
                });
            }
        }

        [HttpGet("Applicable/{vehicleTypeId:int}")]
        [Authorize(Policy = ParkingPermissions.ParkingOperations)]
        public IActionResult GetApplicableRates(int vehicleTypeId)
        {
            if (vehicleTypeId <= 0)
            {
                return BadRequest(new
                {
                    message = "Select a valid vehicle type."
                });
            }

            try
            {
                Response.Headers["Cache-Control"] = "no-store";
                return Ok(_parkingRate.GetApplicableRates(vehicleTypeId));
            }
            catch (KeyNotFoundException exception)
            {
                return NotFound(new { message = exception.Message });
            }
            catch (ArgumentException exception)
            {
                return BadRequest(new { message = exception.Message });
            }
            catch (Exception exception)
            {
                _logger.LogError(exception,"Could not load applicable parking rates.");

                return StatusCode(500, new
                {
                    message = "Could not load applicable rates. Please try again."
                });
            }
        }

        [HttpPost]
        [Authorize(Policy = ParkingPermissions.AdminOnly)]
        public IActionResult CreateRate([FromBody] ParkingRateRequestAPI request)
        {
            string validationError = ValidateRequest(request);

            if (validationError != null)
            {
                return BadRequest(new { message = validationError });
            }

            if (!TryGetActingUserId(out int actingUserId))
            {
                return Unauthorized();
            }

            return ExecuteWrite(() => _parkingRate.CreateRate(request, actingUserId));
        }

        [HttpPut("{rateId:int}")]
        [Authorize(Policy = ParkingPermissions.AdminOnly)]
        public IActionResult UpdateRate(int rateId, [FromBody] ParkingRateRequestAPI request)
        {
            if (rateId <= 0)
            {
                return BadRequest(new
                {
                    message = "A valid rate ID is required."
                });
            }

            string validationError = ValidateRequest(request);

            if (validationError != null)
            {
                return BadRequest(new { message = validationError });
            }

            if (!TryGetActingUserId(out int actingUserId))
            {
                return Unauthorized();
            }

            return ExecuteWrite(() => _parkingRate.UpdateRate(rateId, request, actingUserId));
        }

        private IActionResult ExecuteWrite(Func<ParkingRateResult> operation)
        {
            try
            {
                var result = operation();

                return StatusCode(result.StatusCode, new
                {
                    message = result.Message,
                    rateId = result.RateID
                });
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Could not save a parking rate.");

                return StatusCode(500, new
                {
                    message = "Could not save the parking rate. Please try again."
                });
            }
        }

        private bool TryGetActingUserId(out int userId)
        {
            return int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId) && userId > 0;
        }

        private static string ValidateRequest(ParkingRateRequestAPI request)
        {
            if (string.IsNullOrWhiteSpace(request.RateName))
            {
                return "Rate name is required.";
            }

            if (!request.RateAmount.HasValue)
            {
                return "Rate amount is required.";
            }

            decimal amount = request.RateAmount.Value;

            if (amount < 0 || amount > 9999999999.99m)
            {
                return "Rate amount is outside the permitted range.";
            }

            if (decimal.Round(amount, 2) != amount)
            {
                return "Rate amount must have no more than two decimal places.";
            }

            if (request.EffectiveFrom.HasValue && request.EffectiveTo.HasValue && request.EffectiveTo.Value <= request.EffectiveFrom.Value)
            {
                return "Effective to must be later than effective from.";
            }

            return null;
        }
    }
}