namespace ParkingManagement.Helpers
{
    [AttributeUsage(AttributeTargets.Property)]
    public class TableTypeAttribute : Attribute
    {
        public string TypeName { get; }

        public TableTypeAttribute(string typeName)
        {
            TypeName = typeName;
        }
    }
}