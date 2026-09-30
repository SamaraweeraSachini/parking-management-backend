using ParkingManagement.Authentication;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;
using Microsoft.AspNetCore.Mvc;

namespace ParkingManagement.Controllers.Supplier
{
    [ApiController]
    [Route("api/[controller]")]
    [Authentication(UserTypes = new[] { "Z", "P", "C", "T", "A", "AC", "Q", "AP", "PO" })]
    public class SupplierController : Controller
    {
        private readonly ISupplierDetails _supplierDetails;

        public SupplierController(ISupplierDetails supplierDetails)
        {
            _supplierDetails = supplierDetails;
        }

        [HttpGet("GetSuppliers")]
        public IActionResult GetSuppliers([FromQuery] SupplierRequestAPI requestAPI)
        {
            return Ok(_supplierDetails.GetSuppliers(requestAPI));
        }

        [HttpGet("GetSuppliersByID")]
        public IActionResult GetSuppliersByID([FromQuery] SupplierRequestAPI requestAPI)
        {
            return Ok(_supplierDetails.GetSuppliersByID(requestAPI));
        }

        [HttpPost("AddSupplier")]
        public IActionResult AddSupplier([FromQuery] SupplierRequestAPI requestAPI)
        {
            var userId = HttpContext.Items["UserId"]?.ToString();
            requestAPI.p_uid = userId;
            return Ok(_supplierDetails.AddSupplier(requestAPI));
        }
        [HttpPost("UpdateSupplierDetails")]
        public IActionResult UpdateSupplierDetails([FromQuery] SupplierRequestAPI requestAPI)
        {
            var userId = HttpContext.Items["UserId"]?.ToString();
            requestAPI.p_uid = userId;
            return Ok(_supplierDetails.UpdateSupplierDetails(requestAPI));
        }
    }
}
