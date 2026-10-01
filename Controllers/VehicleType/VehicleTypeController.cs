using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ParkingManagement.Helpers;
using ParkingManagement.Interfaces;
using ParkingManagement.Interfaces.VehicleType;
using ParkingManagement.Models;
using ParkingManagement.Models.VehicleType;

namespace ParkingManagement.Controllers.VehicleType
{
    [ApiController]
    [Route("api/vehicle-types")]
    [Authorize(Policy = ParkingPermissions.ParkingOperations)]
    public class VehicleTypeController : ControllerBase
    {
        private readonly IVehicleType _vehicleTypes;
        private readonly ILogger<VehicleTypeController> _logger;

        public VehicleTypeController(
            IVehicleType vehicleTypes,
            ILogger<VehicleTypeController> logger)
        {
            _vehicleTypes = vehicleTypes;
            _logger = logger;
        }

        // Admins and operators can list active types.
        // Only admins can include inactive types.
        [HttpGet]
        public IActionResult GetVehicleTypes(
            [FromQuery] bool includeInactive = false)
        {
            if (includeInactive &&
                !User.IsInRole(ParkingPermissions.AdminRole))
            {
                return Forbid();
            }

            return Run(() => _vehicleTypes.GetVehicleTypes(includeInactive));
        }

        // Includes inactive types for detail/history access.
        [HttpGet("{id:int}")]
        public IActionResult GetVehicleTypeByID(int id)
        {
            if (id <= 0)
            {
                return InvalidID();
            }

            return Run(() => _vehicleTypes.GetVehicleTypeByID(id));
        }

        [HttpPost]
        //[Authorize(Policy = ParkingPermissions.AdminOnly)]
        public IActionResult CreateVehicleType(
            [FromBody] VehicleTypeModel model)
        {
            return Write(
                actionType: 3,
                model: model);
        }

        [HttpPut("{id:int}")]
        //[Authorize(Policy = ParkingPermissions.AdminOnly)]
        public IActionResult UpdateVehicleType(
            int id,
            [FromBody] VehicleTypeModel model)
        {
            return Write(
                actionType: 4,
                vehicleTypeID: id,
                model: model);
        }

        [HttpPatch("{id:int}/deactivate")]
        //[Authorize(Policy = ParkingPermissions.AdminOnly)]
        public IActionResult DeactivateVehicleType(int id)
        {
            return Write(
                actionType: 5,
                vehicleTypeID: id);
        }

        [HttpPatch("{id:int}/reactivate")]
        //[Authorize(Policy = ParkingPermissions.AdminOnly)]
        public IActionResult ReactivateVehicleType(int id)
        {
            return Write(
                actionType: 6,
                vehicleTypeID: id);
        }

        private IActionResult Write(
            int actionType,
            int? vehicleTypeID = null,
            VehicleTypeModel model = null)
        {
            if (actionType != 3 &&
                (!vehicleTypeID.HasValue || vehicleTypeID.Value <= 0))
            {
                return InvalidID();
            }

            if (actionType == 3 || actionType == 4)
            {
                if (model == null ||
                    string.IsNullOrWhiteSpace(model.TypeName))
                {
                    return BadRequest(new Response
                    {
                        StatusCode = 400,
                        Result = "Vehicle type name is required."
                    });
                }
            }

            if (!int.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out int userID) || userID <= 0)
            {
                return Unauthorized(new Response
                {
                    StatusCode = 401,
                    Result = "A valid logged-in user is required."
                });
            }

            return actionType switch
            {
                3 => Run(() => _vehicleTypes.AddVehicleType(
                    model,
                    userID)),

                4 => Run(() => _vehicleTypes.UpdateVehicleType(
                    vehicleTypeID!.Value,
                    model,
                    userID)),

                5 => Run(() => _vehicleTypes.DeactivateVehicleType(
                    vehicleTypeID!.Value,
                    userID)),

                6 => Run(() => _vehicleTypes.ReactivateVehicleType(
                    vehicleTypeID!.Value,
                    userID)),

                _ => BadRequest(new Response
                {
                    StatusCode = 400,
                    Result = "Invalid vehicle type operation."
                })
            };
        }

        private IActionResult Run(Func<Response> operation)
        {
            try
            {
                Response result = operation();

                return StatusCode(result.StatusCode, result);
            }
            catch (Exception exception)
            {
                _logger.LogError(
                    exception,
                    "Vehicle type operation failed.");

                return StatusCode(500, new Response
                {
                    StatusCode = 500,
                    Result = "Vehicle type management is temporarily unavailable."
                });
            }
        }

        private IActionResult InvalidID()
        {
            return BadRequest(new Response
            {
                StatusCode = 400,
                Result = "A valid vehicle type ID is required."
            });
        }
    }
}