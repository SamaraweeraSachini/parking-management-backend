using ParkingManagement.DataBaseConnectivity.MSSQL;
using ParkingManagement.Helpers;
using ParkingManagement.Middleware;
using ParkingManagement.Models;
using Microsoft.Data.SqlClient;
using System;
using System.Collections;
using System.Data;
using System.Reflection;

namespace ParkingManagement.Database_Layer
{
    internal class DBconnect : IDisposable
    {
        private readonly string _connectionString;

        public DBconnect(string clientCode)
        {
            if (string.IsNullOrWhiteSpace(clientCode))
            {
                throw new ArgumentException(  "Client code cannot be empty.",  nameof(clientCode));
            }

            _connectionString = ConnectionManager.GetConnection(clientCode);
        }

        public DBconnect()
        {
            string clientCode = ClientContext.ClientCode;

            if (string.IsNullOrWhiteSpace(clientCode))
            {
                throw new Exception(  "Client code was not found for the current request.");
            }

            _connectionString = ConnectionManager.GetConnection(clientCode);
        }

        public SqlConnection GetOpenConnection()
        {
            SqlConnection connection = new SqlConnection(_connectionString);
            connection.Open();
            return connection;
        }

        public SqlDataReader ReadTable(string readStr)
        {
            SqlConnection connection = GetOpenConnection();
            SqlCommand command = new SqlCommand(readStr, connection);
            return command.ExecuteReader( CommandBehavior.CloseConnection);
        }

        public bool AddEditDel(string addEditDelStr)
        {
            using SqlConnection connection = GetOpenConnection();
            using SqlCommand command =  new SqlCommand(addEditDelStr, connection);
            int affectedRows = command.ExecuteNonQuery();
            return affectedRows > 0;
        }
        public ProcedureDBModel ProcedureRead(
            RequestAPI requestAPI,
            string procedureName)
        {
            ProcedureDBModel result = new ProcedureDBModel();

            using SqlConnection connection = GetOpenConnection();
            using SqlCommand cmd = new SqlCommand(procedureName, connection);

            cmd.CommandType = CommandType.StoredProcedure;


            // ============================================================
            // ResultStatusCode
            // ============================================================

            SqlParameter statusCodeParam =
                new SqlParameter("@ResultStatusCode", SqlDbType.Int)
                {
                    Direction = ParameterDirection.Output
                };

            cmd.Parameters.Add(statusCodeParam);


            // ============================================================
            // Result
            // ============================================================

            SqlParameter resultParam =
                new SqlParameter("@Result", SqlDbType.VarChar, -1)
                {
                    Direction = ParameterDirection.Output
                };

            cmd.Parameters.Add(resultParam);


            // ============================================================
            // ExceptionMessage
            // ============================================================

            SqlParameter exceptionParam =
                new SqlParameter("@ExceptionMessage", SqlDbType.VarChar, -1)
                {
                    Direction = ParameterDirection.Output
                };

            cmd.Parameters.Add(exceptionParam);


            // ============================================================
            // Map input properties
            // ============================================================

            Type type = requestAPI.GetType();

            PropertyInfo[] properties =
                type.GetProperties(
                    BindingFlags.Public |
                    BindingFlags.Instance);


            foreach (PropertyInfo property in properties)
            {
                string paramName = "@" + property.Name;

                object value =
                    property.GetValue(requestAPI);


                // ========================================================
                // Check whether property is a TVP
                // ========================================================

                TableTypeAttribute tableTypeAttribute =
                    property.GetCustomAttribute<TableTypeAttribute>();


                if (tableTypeAttribute != null)
                {
                    DataTable dataTable =
                        ConvertListToDataTable(
                            value,
                            property.PropertyType);


                    SqlParameter tableParameter =
                        new SqlParameter(
                            paramName,
                            SqlDbType.Structured)
                        {
                            Direction = ParameterDirection.Input,

                            TypeName =
                                tableTypeAttribute.TypeName,

                            Value = dataTable
                        };


                    cmd.Parameters.Add(tableParameter);

                    continue;
                }


                // ========================================================
                // Normal parameter
                // ========================================================

                object parameterValue =
                    value ?? DBNull.Value;


                SqlParameter normalParameter =
                    new SqlParameter(
                        paramName,
                        SqlDbType.NVarChar)
                    {
                        Direction = ParameterDirection.Input,
                        Value = parameterValue
                    };


                cmd.Parameters.Add(normalParameter);
            }


            // ============================================================
            // Execute
            // ============================================================

            try
            {
                using SqlDataAdapter da =
                    new SqlDataAdapter(cmd);

                DataSet ds = new DataSet();

                da.Fill(ds);

                result.ResultDataSet = ds;


                if (ds.Tables.Count > 0)
                {
                    result.ResultDataTable = ds.Tables[0];
                }


                // ========================================================
                // Output parameters
                // ========================================================

                result.ResultStatusCode =
                    statusCodeParam.Value != DBNull.Value
                        ? statusCodeParam.Value.ToString()
                        : "1";


                result.Result =
                    resultParam.Value != DBNull.Value
                        ? resultParam.Value.ToString()
                        : "Success";


                result.ExceptionMessage =
                    exceptionParam.Value != DBNull.Value
                        ? exceptionParam.Value.ToString()
                        : null;
            }
            catch (Exception ex)
            {
                result.ResultStatusCode = "-1";
                result.ExceptionMessage = ex.Message;
            }


            return result;
        }

        private DataTable ConvertListToDataTable(
    object value,
    Type propertyType)
        {
            DataTable table = new DataTable();


            if (value == null)
            {
                return table;
            }


            // ============================================================
            // Get List<T> item type
            // ============================================================

            Type itemType =
                propertyType.GetGenericArguments()[0];


            PropertyInfo[] itemProperties =
                itemType.GetProperties(
                    BindingFlags.Public |
                    BindingFlags.Instance);


            // ============================================================
            // Create DataTable columns
            // ============================================================

            foreach (PropertyInfo property in itemProperties)
            {
                TableColumnAttribute columnAttribute =
                    property.GetCustomAttribute<TableColumnAttribute>();


                string columnName;


                if (columnAttribute != null)
                {
                    columnName = columnAttribute.ColumnName;
                }
                else
                {
                    columnName = property.Name;
                }


                Type columnType =
                    Nullable.GetUnderlyingType(
                        property.PropertyType)
                    ?? property.PropertyType;


                table.Columns.Add(
                    columnName,
                    columnType);
            }


            // ============================================================
            // Add DataTable rows
            // ============================================================

            IEnumerable items =
                (IEnumerable)value;


            foreach (object item in items)
            {
                DataRow row = table.NewRow();


                foreach (PropertyInfo property in itemProperties)
                {
                    TableColumnAttribute columnAttribute =
                        property.GetCustomAttribute<TableColumnAttribute>();


                    string columnName;


                    if (columnAttribute != null)
                    {
                        columnName =
                            columnAttribute.ColumnName;
                    }
                    else
                    {
                        columnName =
                            property.Name;
                    }


                    object propertyValue =
                        property.GetValue(item);


                    row[columnName] =
                        propertyValue ?? DBNull.Value;
                }


                table.Rows.Add(row);
            }


            return table;
        }
        //public ProcedureDBModel ProcedureRead(RequestAPI requestAPI, string procedureName)
        //{
        //    ProcedureDBModel result =   new ProcedureDBModel();
        //    using SqlConnection connection =  GetOpenConnection();
        //    using SqlCommand cmd =   new SqlCommand(procedureName, connection);

        //    cmd.CommandType =  CommandType.StoredProcedure;

        //    // ResultStatusCode
        //    SqlParameter statusCodeParam = new SqlParameter( "@ResultStatusCode", SqlDbType.Int)
        //        {
        //            Direction = ParameterDirection.Output
        //        };

        //    cmd.Parameters.Add(statusCodeParam);

        //    // Result
        //    SqlParameter resultParam =  new SqlParameter(  "@Result", SqlDbType.VarChar, -1)
        //        {
        //            Direction = ParameterDirection.Output
        //        };

        //    cmd.Parameters.Add(resultParam);

        //    // ExceptionMessage
        //    SqlParameter exceptionParam = new SqlParameter(  "@ExceptionMessage", SqlDbType.VarChar, -1)
        //        {
        //            Direction = ParameterDirection.Output
        //        };

        //    cmd.Parameters.Add(exceptionParam);

        //    // Map input properties
        //    Type type = requestAPI.GetType();

        //    PropertyInfo[] properties =   type.GetProperties(  BindingFlags.Public |  BindingFlags.Instance);

        //    foreach (PropertyInfo property in properties)
        //    {
        //        string paramName = "@" + property.Name;

        //        object value =  property.GetValue(requestAPI)   ?? DBNull.Value;

        //        SqlParameter param =  new SqlParameter(paramName,SqlDbType.NVarChar)
        //            {
        //                Direction = ParameterDirection.Input,
        //                Value = value
        //            };

        //        cmd.Parameters.Add(param);
        //    }

        //    try
        //    {
        //        using SqlDataAdapter da = new SqlDataAdapter(cmd);
        //        DataSet ds = new DataSet();
        //        da.Fill(ds);
        //        result.ResultDataSet = ds;

        //        if (ds.Tables.Count > 0)
        //        {
        //            result.ResultDataTable = ds.Tables[0];
        //        }

        //        // Output parameters
        //        result.ResultStatusCode = statusCodeParam.Value != DBNull.Value  ? statusCodeParam.Value.ToString() : "1";
        //        result.Result =  resultParam.Value != DBNull.Value ? resultParam.Value.ToString()  : "Success";
        //        result.ExceptionMessage =  exceptionParam.Value != DBNull.Value   ? exceptionParam.Value.ToString()    : null;

        //    }
        //    catch (Exception ex)
        //    {
        //        result.ResultStatusCode = "-1";
        //        result.ExceptionMessage = ex.Message;
        //    }

        //    return result;
        //}

        internal SqlDataReader ReadTable(
            SqlCommand command)
        {
            if (command == null)
            {
                throw new ArgumentNullException(nameof(command));
            }

            if (command.Connection == null)
            {
                command.Connection = GetOpenConnection();
            }
            else if (command.Connection.State !=  ConnectionState.Open)
            {
                command.Connection.Open();
            }

            return command.ExecuteReader(
                CommandBehavior.CloseConnection);
        }

        public void Dispose()
        {
            // No persistent connection is maintained.
            // Connections are disposed where they are used.
        }
    }
}