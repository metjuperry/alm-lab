using System;

namespace Plugins.Warehouse
{
    public class ValidateWarehouseTransactionPlugin : PluginBase
    {
        public ValidateWarehouseTransactionPlugin(string unsecureConfiguration, string secureConfiguration)
            : base(typeof(ValidateWarehouseTransactionPlugin)) { }

        protected override void ExecuteDataversePlugin(ILocalPluginContext context)
        {
            if (context == null) throw new ArgumentNullException(nameof(context));
            WarehouseStock.Execute(context.PluginExecutionContext,
                context.OrgSvcFactory.CreateOrganizationService(context.PluginExecutionContext.UserId), false);
        }
    }
}
