using ParkingManagement.Middleware;
using ParkingManagement.Properties;
using System;
using System.IO;

namespace ParkingManagement.Static
{
    public static class LogHandler
    {
        public static void WriteToLog(string exceptionMsg,string Result,string methodName)
        {
            DateTime now = DateTime.Now;

            string basePath = Resources.ExceptionLogPath;

            string clientCode = ClientContext.ClientCode;

            if (string.IsNullOrWhiteSpace(clientCode))
            {
                clientCode = "Default";
            }

            string clientFolder = Path.Combine(basePath, clientCode);

            if (!Directory.Exists(clientFolder))
            {
                Directory.CreateDirectory(clientFolder);
            }

            string dateSuffix = now.ToString("yyyyMMdd");

            string fileName = $"{dateSuffix}.txt";

            string filePath = Path.Combine(clientFolder, fileName);

            string message = $"{now:yyyy-MM-dd HH:mm:ss} ~ " + $"{methodName} ~ " + $"{exceptionMsg}" + $"{Result}";

            using (StreamWriter writer = File.AppendText(filePath))
            {
                writer.WriteLine(message);
            }
        }
    }
}