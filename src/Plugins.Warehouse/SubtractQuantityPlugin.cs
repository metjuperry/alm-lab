using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;
using System;

namespace Plugins.Warehouse
{
    public class SubtractQuantityPlugin : PluginBase
    {
        public SubtractQuantityPlugin(string unsecureConfiguration, string secureConfiguration)
            : base(typeof(SubtractQuantityPlugin))
        {
        }

        protected override void ExecuteDataversePlugin(ILocalPluginContext localPluginContext)
        {
            if (localPluginContext == null)
            {
                throw new ArgumentNullException(nameof(localPluginContext));
            }

            var context = localPluginContext.PluginExecutionContext;
            var serviceFactory = localPluginContext.OrgSvcFactory;
            var service = serviceFactory.CreateOrganizationService(context.UserId);

            if (!(context.InputParameters["Target"] is Entity target) || target.LogicalName != "almlab_warehousetransaction")
                return;

            if (!target.Contains("almlab_quantity") || !target.Contains("almlab_itemid") || !target.Contains("almlab_transactiontype"))
                return;

            var quantity = (int)target["almlab_quantity"];
            var itemRef = (EntityReference)target["almlab_itemid"];
            var transactionType = (OptionSetValue)target["almlab_transactiontype"];

            var item = service.Retrieve("almlab_warehouseitem", itemRef.Id, new ColumnSet("almlab_availablequantity"));
            var available = item.Contains("almlab_availablequantity") ? (int)item["almlab_availablequantity"] : 0;

            // Inbound (1) = add stock, Outbound (2) = subtract stock
            if (transactionType.Value == 1)
                item["almlab_availablequantity"] = available + quantity;
            else if (transactionType.Value == 2)
                item["almlab_availablequantity"] = available - quantity;
            else
                return;

            service.Update(item);
        }
    }
}
