using System;

namespace Plugins.Warehouse
{
    public class SubtractQuantityPlugin : PluginBase
    {
        public SubtractQuantityPlugin(string unsecureConfiguration, string secureConfiguration)
            : base(typeof(SubtractQuantityPlugin)) { }

        protected override void ExecuteDataversePlugin(ILocalPluginContext context)
        {
            if (context == null) throw new ArgumentNullException(nameof(context));
            WarehouseStock.Execute(context.PluginExecutionContext,
                context.OrgSvcFactory.CreateOrganizationService(context.PluginExecutionContext.UserId), true);
        }
    }
}
