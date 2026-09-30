namespace ParkingManagement.Models
{
    public class SupplierRequestAPI : RequestAPI
    {
     
        public string p_supCode { get; set; }
        public string p_supplierName { get; set; }
        public string p_address { get; set; }
        public string p_tel { get; set; }
        public string p_fax { get; set; }
        public string p_email { get; set; }
        public string p_ledgerCode { get; set; }
        public string p_isActive { get; set; }
        public string p_remark { get; set; }

    }
}
