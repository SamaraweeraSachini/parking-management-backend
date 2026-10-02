namespace ParkingManagement.Models
{
    public class ParkingRateModel
    {
        public int RateID { get; set; }
        public int VehicleTypeID { get; set; }

        public string RateName { get; set; } = "";
        public decimal RateAmount { get; set; }
        public string RateUnit { get; set; } = "";

        public DateTime EffectiveFrom { get; set; }
        public DateTime? EffectiveTo { get; set; }

        public bool ActiveStatus { get; set; }
    }

    public class RateVehicleTypeModel
    {
        public int VehicleTypeID { get; set; }
        public string TypeName { get; set; } = "";
    }

    public class ApplicableRateModel
    {
        public int RateID { get; set; }
        public int VehicleTypeID { get; set; }

        public string RateName { get; set; } = "";
        public decimal RateAmount { get; set; }
        public string RateUnit { get; set; } = "";

        public DateTime EffectiveFrom { get; set; }
        public DateTime? EffectiveTo { get; set; }
    }

    public class ParkingRateResult
    {
        public int StatusCode { get; set; }
        public string Message { get; set; } = "";
        public int? RateID { get; set; }
    }
}