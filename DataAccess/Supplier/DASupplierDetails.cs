using ParkingManagement.Database_Layer;
using ParkingManagement.Interfaces;
using ParkingManagement.Models;
using ParkingManagement.Static;
using System.Data;

namespace ParkingManagement.DataAccess
{
    public class DASupplierDetails : ISupplierDetails
    {

        private readonly string ProcedureName = "F28_SUPPLIERDETAILS_PROC";

        public Response GetSuppliers(SupplierRequestAPI requestAPI)
        {
            Response result = new Response();
            requestAPI.ActionType = 1;

            using (var dbConnect = new DBconnect())
            {
                ProcedureDBModel res = dbConnect.ProcedureRead(requestAPI, ProcedureName);

                if (res.ResultStatusCode == "1")
                {
                    List<SupplierModel> supplierList = new List<SupplierModel>();

                    foreach (DataRow row in res.ResultDataTable.Rows)
                    {
                        SupplierModel supplier = new SupplierModel
                        {
                            FSD_SUP_CODE = row["FSD_SUP_CODE"].ToString(),
                            FSD_SUPPLIER_NAME = row["FSD_SUPPLIER_NAME"].ToString(),
                            FSD_ADDRESS = row["FSD_ADDRESS"].ToString(),
                            FSD_TEL = row["FSD_TEL"].ToString(),
                            FSD_FAX = row["FSD_FAX"].ToString(),
                            FSD_EMAIL = row["FSD_EMAIL"].ToString(),
                            FSD_LEDGER_CODE = row["FSD_LEDGER_CODE"].ToString(),
                            FSD_REMARK = row["FSD_REMARK"].ToString(),
                            FSD_IS_ACTIVE = row["FSD_IS_ACTIVE"].ToString(),
                            FSD_CREATED_BY = row["FSD_CREATED_BY"].ToString(),
                            FSD_CREATED_DATE = row["FSD_CREATED_DATE"].ToString(),
                            FSD_UPDATED_BY = row["FSD_UPDATED_BY"].ToString(),
                            FSD_UPDATED_DATE = row["FSD_UPDATED_DATE"].ToString()
                        };
                        supplierList.Add(supplier);
                    }

                    result.StatusCode = 200;
                    result.ResultSet = supplierList;        
                }
                else
                {
                    LogHandler.WriteToLog(res.ExceptionMessage, res.Result, System.Reflection.MethodBase.GetCurrentMethod().Name);
                    result.StatusCode = 500;
                    result.Result = res.Result;
                }
            }

            return result;
        }

        public Response GetSuppliersByID(SupplierRequestAPI requestAPI)
        {

            Response result = new Response();
            requestAPI.ActionType = 2;

            using (var dbConnect = new DBconnect())
            {
                ProcedureDBModel res = dbConnect.ProcedureRead(requestAPI, ProcedureName);

                if (res.ResultStatusCode == "1")
                {
                    List<SupplierModel> supplierList = new List<SupplierModel>();

                    foreach (DataRow row in res.ResultDataTable.Rows)
                    {
                        SupplierModel supplier = new SupplierModel
                        {
                            FSD_SUP_CODE = row["FSD_SUP_CODE"].ToString(),
                            FSD_SUPPLIER_NAME = row["FSD_SUPPLIER_NAME"].ToString(),
                            FSD_ADDRESS = row["FSD_ADDRESS"].ToString(),
                            FSD_TEL = row["FSD_TEL"].ToString(),
                            FSD_FAX = row["FSD_FAX"].ToString(),
                            FSD_EMAIL = row["FSD_EMAIL"].ToString(),
                            FSD_LEDGER_CODE = row["FSD_LEDGER_CODE"].ToString(),
                            FSD_REMARK = row["FSD_REMARK"].ToString(),
                            FSD_IS_ACTIVE = row["FSD_IS_ACTIVE"].ToString(),
                            FSD_CREATED_BY = row["FSD_CREATED_BY"].ToString(),
                            FSD_CREATED_DATE = row["FSD_CREATED_DATE"].ToString(),
                            FSD_UPDATED_BY = row["FSD_UPDATED_BY"].ToString(),
                            FSD_UPDATED_DATE = row["FSD_UPDATED_DATE"].ToString()
                        };
                        supplierList.Add(supplier);
                    }

                    result.StatusCode = 200;
                    result.ResultSet = supplierList;
                }
                else
                {
                    LogHandler.WriteToLog(res.ExceptionMessage, res.Result, System.Reflection.MethodBase.GetCurrentMethod().Name);
                    result.StatusCode = 500;
                    result.Result = res.Result;
                }
            }

            return result;
        }
        public Response AddSupplier(SupplierRequestAPI requestAPI)
        {
            Response result = new Response();
            requestAPI.ActionType = 3;

            using (var dbConnect = new DBconnect())
            {
                ProcedureDBModel res = dbConnect.ProcedureRead(requestAPI, ProcedureName);

                if (res.ResultStatusCode == "1")
                {
                    result.StatusCode = 200;
                    result.Result = res.Result;
                }
                else
                {
                    LogHandler.WriteToLog(res.ExceptionMessage, res.Result, System.Reflection.MethodBase.GetCurrentMethod().Name);
                    result.StatusCode = 500;
                    result.Result = res.Result;
                }
            }
            return result;
        }


        public Response UpdateSupplierDetails(SupplierRequestAPI requestAPI)
        {
            Response result = new Response();
            requestAPI.ActionType = 4;

            using (var dbConnect = new DBconnect())
            {
                ProcedureDBModel res = dbConnect.ProcedureRead(requestAPI, ProcedureName);

                if (res.ResultStatusCode == "1")
                {
                    result.StatusCode = 200;
                    result.Result = res.Result;
                }
                else
                {
                    LogHandler.WriteToLog(res.ExceptionMessage, res.Result, System.Reflection.MethodBase.GetCurrentMethod().Name);
                    result.StatusCode = 500;
                    result.Result = res.Result;
                }
            }
            return result;
        }
    }
}
