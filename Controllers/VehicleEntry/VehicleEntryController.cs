using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ParkingManagement.Helpers;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;

namespace ParkingManagement.Controllers.VehicleEntry
{
    [ApiController]
    [Route("api/VehicleEntry")]
    [Authorize(Policy = ParkingPermissions.ParkingOperations)]
    public class VehicleEntryController : ControllerBase
    {
        private readonly IVehicleEntry _vehicleEntry;
        private readonly ILogger<VehicleEntryController> _logger;

        public VehicleEntryController(IVehicleEntry vehicleEntry, ILogger<VehicleEntryController> logger)
        {
            _vehicleEntry = vehicleEntry;
            _logger = logger;
        }

        [HttpGet("VehicleTypes")]
        public IActionResult GetVehicleTypes()
        {
            try
            {
                Response.Headers["Cache-Control"] = "no-store";
                return Ok(_vehicleEntry.GetActiveVehicleTypes());
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Could not load entry vehicle types.");

                return StatusCode(500, new
                {
                    message = "Could not load vehicle types. Please try again."
                });
            }
        }

        [HttpGet("AvailableSpaces/{vehicleTypeId:int}")]
        public IActionResult GetAvailableSpaces(int vehicleTypeId)
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
                return Ok(_vehicleEntry.GetAvailableSpaces(vehicleTypeId));
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Could not load available entry spaces.");

                return StatusCode(500, new
                {
                    message = "Could not load available spaces. Please try again."
                });
            }
        }

        [HttpPost("Daily")]
        public IActionResult CreateDailyEntry([FromBody] DailyEntryRequestAPI request)
        {
            if (string.IsNullOrWhiteSpace(request.VehicleNumber))
            {
                return BadRequest(new
                {
                    message = "Vehicle number is required."
                });
            }

            if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out int operatorUserId) || operatorUserId <= 0)
            {
                return Unauthorized();
            }

            if (!string.IsNullOrWhiteSpace(request.MobileNumber))
            {
                string mobileNumber = request.MobileNumber.Trim();

                if (!System.Text.RegularExpressions.Regex.IsMatch(mobileNumber, @"^[0-9]{10}$"))
                {
                    return BadRequest(new
                    {
                        message =
                            "Mobile number must contain exactly 10 digits."
                    });
                }
            }

            try
            {
                var result = _vehicleEntry.CreateDailyEntry(request, operatorUserId);

                return StatusCode(result.StatusCode, new
                {
                    message = result.Message,
                    ticketID = result.TicketID,
                    ticketNumber = result.TicketNumber,
                    vehicleNumber = result.VehicleNumber,
                    spaceID = result.SpaceID,
                    entryDateTime = result.EntryDateTime,
                    parkingType = "DAILY"
                });
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Could not register daily vehicle entry.");

                return StatusCode(500, new
                {
                    message = "Could not register entry. Check current parking " + "before retrying if the result is uncertain."
                });
            }
        }

        [HttpPost("Monthly")]
        public IActionResult CreateMonthlyEntry([FromBody] MonthlyEntryRequestAPI request)
            {
                if (string.IsNullOrWhiteSpace(request.VehicleNumber))
                {
                    return BadRequest(new
                    {
                        message = "Vehicle number is required."
                    });
                }

                if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out int operatorUserId) || operatorUserId <= 0)
                {
                    return Unauthorized();
                }

                try
                {
                    var result = _vehicleEntry.CreateMonthlyEntry(request, operatorUserId);

                    return StatusCode(result.StatusCode, new
                    {
                        message = result.Message,
                        ticketID = result.TicketID,
                        ticketNumber = result.TicketNumber,
                        vehicleNumber = result.VehicleNumber,
                        spaceID = result.SpaceID,
                        entryDateTime = result.EntryDateTime,
                        parkingType = "MONTHLY",
                        contractID = result.ContractID,
                        contractNumber = result.ContractNumber
                    });
                }
                catch (Exception exception)
                {
                    _logger.LogError(exception, "Could not register monthly vehicle entry.");

                    return StatusCode(500, new
                    {
                        message = "Could not register entry. Check current parking " + "before retrying if the result is uncertain."
                    });
                }
        }
    }
}