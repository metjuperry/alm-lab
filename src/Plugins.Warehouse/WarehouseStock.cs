using System;
using System.Collections.Generic;
using System.Linq;
using System.ServiceModel;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Messages;
using Microsoft.Xrm.Sdk.Query;

namespace Plugins.Warehouse
{
    internal static class WarehouseStock
    {
        internal const string Movement = "almlab_warehousetransaction";
        internal const string Item = "almlab_warehouseitem";
        internal const string Quantity = "almlab_quantity";
        internal const string ItemId = "almlab_itemid";
        internal const string Type = "almlab_transactiontype";
        internal const string Available = "almlab_availablequantity";

        internal static IDictionary<Guid, long> Deltas(IPluginExecutionContext context)
        {
            var deltas = new Dictionary<Guid, long>();
            Entity before = null;
            if (context.MessageName == "Update" || context.MessageName == "Delete")
            {
                if (!context.PreEntityImages.Contains("Before"))
                    throw new InvalidPluginExecutionException("The stock step requires its Before pre-image. Contact the app administrator.");
                before = context.PreEntityImages["Before"];
                AddEffect(deltas, before, -1);
            }
            if (context.MessageName == "Create" || context.MessageName == "Update")
            {
                var target = context.InputParameters["Target"] as Entity;
                if (target == null)
                    throw new InvalidPluginExecutionException("A movement record is required.");
                var after = new Entity(Movement);
                if (before != null)
                    foreach (var attribute in before.Attributes) after[attribute.Key] = attribute.Value;
                foreach (var attribute in target.Attributes) after[attribute.Key] = attribute.Value;
                AddEffect(deltas, after, 1);
            }
            return deltas;
        }

        private static void AddEffect(IDictionary<Guid, long> deltas, Entity movement, int direction)
        {
            var reference = movement.GetAttributeValue<EntityReference>(ItemId);
            var quantity = movement.GetAttributeValue<int>(Quantity);
            var type = movement.GetAttributeValue<OptionSetValue>(Type);
            if (reference == null || reference.LogicalName != Item || reference.Id == Guid.Empty)
                throw new InvalidPluginExecutionException("Choose a warehouse item.");
            if (quantity <= 0)
                throw new InvalidPluginExecutionException("Movement quantity must be greater than zero.");
            if (type == null || (type.Value != 100000000 && type.Value != 100000001))
                throw new InvalidPluginExecutionException("Choose Inbound or Outbound.");
            var effect = (long)quantity * (type.Value == 100000000 ? 1 : -1) * direction;
            deltas.TryGetValue(reference.Id, out var current);
            deltas[reference.Id] = current + effect;
        }

        internal static void Execute(IPluginExecutionContext context, IOrganizationService service, bool write)
        {
            if (context.PrimaryEntityName == Item)
            {
                var target = context.InputParameters["Target"] as Entity;
                if (target == null || !target.Contains(Available)) return;
                if (context.ParentContext?.SharedVariables.Contains("WarehouseStockWrite") == true) return;
                if (context.MessageName == "Create" && target.GetAttributeValue<int>(Available) == 0) return;
                if (context.MessageName == "Update")
                {
                    var current = service.Retrieve(Item, target.Id, new ColumnSet(Available));
                    if (target.GetAttributeValue<int>(Available) == current.GetAttributeValue<int>(Available))
                    {
                        // Strip an unchanged value so a concurrent movement cannot be
                        // overwritten by a catalogue form submitting a stale full record.
                        target.Attributes.Remove(Available);
                        return;
                    }
                }
                throw new InvalidPluginExecutionException("Record or correct a movement to change stock. New items start at zero.");
            }
            if (context.PrimaryEntityName != Movement) return;
            if (context.MessageName != "Create" && context.MessageName != "Update" && context.MessageName != "Delete") return;
            if (write && !context.IsInTransaction)
                throw new InvalidPluginExecutionException("Stock accounting must run synchronously inside the movement transaction.");

            var updates = new List<Entity>();
            foreach (var delta in Deltas(context).Where(pair => pair.Value != 0).OrderBy(pair => pair.Key))
            {
                var item = service.Retrieve(Item, delta.Key, new ColumnSet(Available));
                var available = item.GetAttributeValue<int>(Available);
                var balance = (long)available + delta.Value;
                if (balance < 0)
                    throw new InvalidPluginExecutionException(
                        $"Not enough product in stock. Available: {available}, requested: {-delta.Value}.");
                if (balance > int.MaxValue)
                    throw new InvalidPluginExecutionException("The resulting stock quantity exceeds the supported limit.");
                if (write && string.IsNullOrWhiteSpace(item.RowVersion))
                    throw new InvalidPluginExecutionException("Stock row version is unavailable. Enable optimistic concurrency on Warehouse Item.");
                var update = new Entity(Item, item.Id) { RowVersion = item.RowVersion };
                update[Available] = (int)balance;
                updates.Add(update);
            }
            if (!write) return;
            context.SharedVariables["WarehouseStockWrite"] = true;
            foreach (var update in updates)
            {
                try
                {
                    service.Execute(new UpdateRequest
                    {
                        Target = update,
                        ConcurrencyBehavior = ConcurrencyBehavior.IfRowVersionMatches
                    });
                }
                catch (FaultException<OrganizationServiceFault> ex) when (ex.Detail.ErrorCode == -2147088254)
                {
                    // Throwing rolls back the movement and any earlier item update.
                    throw new InvalidPluginExecutionException("Stock changed while saving. Refresh the item and retry the movement.", ex);
                }
            }
        }
    }
}
