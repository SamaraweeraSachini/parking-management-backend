namespace ParkingManagement.Helpers
{
    [AttributeUsage(AttributeTargets.Property)]
    public class TableColumnAttribute : Attribute
    {
        public string ColumnName { get; }

        public TableColumnAttribute(string columnName)
        {
            ColumnName = columnName;
        }
    }
}