
using ParkingManagement.Properties;
using System;
using System.Collections.Generic;
using System.IO;

namespace ParkingManagement.DataBaseConnectivity.MSSQL
{
    public static class ConnectionManager
    {
        private static readonly Dictionary<string, string> Connections;

        static ConnectionManager()
        {
            string filePath = Resources.Connection;

            if (string.IsNullOrWhiteSpace(filePath))
            {
                throw new Exception("Resources.Connection is empty.");
            }

            if (!File.Exists(filePath))
            {
                throw new FileNotFoundException( "Connection configuration file not found. " +   "Resource path: [" + filePath + "]",   filePath);
            }

            Connections = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            foreach (string line in File.ReadAllLines(filePath))
            {
                if (string.IsNullOrWhiteSpace(line))
                    continue;

                string value = line.Trim();

                if (value.StartsWith("#"))
                    continue;

                int index = value.IndexOf('=');

                if (index <= 0)
                    continue;

                string key = value.Substring(0, index).Trim();

                string connectionString = value.Substring(index + 1).Trim();

                if (!string.IsNullOrWhiteSpace(key) && !string.IsNullOrWhiteSpace(connectionString))
                {
                    Connections[key] = connectionString;
                }
            }
        }

        public static string GetConnection(string clientCode)
        {
            if (string.IsNullOrWhiteSpace(clientCode))
            {
                throw new ArgumentException( "Client code cannot be empty.",  nameof(clientCode));
            }

            if (Connections.TryGetValue(  clientCode,  out string connectionString))
            {
                return connectionString;
            }

            throw new KeyNotFoundException( $"Connection for client '{clientCode}' not found.");
        }
    }
}