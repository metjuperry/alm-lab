using System;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;
using FakeXrmEasy.Plugins;
using Plugins.Warehouse;

namespace Tests.Plugins
{
    [TestClass]
    public class ValidateWarehouseTransactionPluginTests : FakeXrmEasyTestBase
    {
        private const int Inbound = 100000000;
        private const int Outbound = 100000001;

        private Entity SeedItem(int available)
        {
            var item = new Entity("__PREFIX___warehouseitem") { Id = Guid.NewGuid() };
            item["__PREFIX___availablequantity"] = available;
            _context.Initialize(new[] { item });
            return item;
        }

        private Entity MakeTransaction(Guid itemId, int quantity, int type)
        {
            var transaction = new Entity("__PREFIX___warehousetransaction") { Id = Guid.NewGuid() };
            transaction["__PREFIX___quantity"] = quantity;
            transaction["__PREFIX___itemid"] = new EntityReference("__PREFIX___warehouseitem", itemId);
            transaction["__PREFIX___transactiontype"] = new OptionSetValue(type);
            return transaction;
        }

        private void Execute(Entity target)
        {
            var pluginContext = _context.GetDefaultPluginContext();
            pluginContext.MessageName = "Create";
            pluginContext.PrimaryEntityName = "__PREFIX___warehousetransaction";
            pluginContext.InputParameters["Target"] = target;

            var plugin = new ValidateWarehouseTransactionPlugin(string.Empty, string.Empty);
            _context.ExecutePluginWith(pluginContext, plugin);
        }

        [TestMethod]
        public void Outbound_With_Enough_Stock_Does_Not_Throw()
        {
            var item = SeedItem(available: 10);

            Execute(MakeTransaction(item.Id, quantity: 3, Outbound));

            var reloaded = _service.Retrieve("__PREFIX___warehouseitem", item.Id, new ColumnSet("__PREFIX___availablequantity"));
            Assert.AreEqual(10, reloaded.GetAttributeValue<int>("__PREFIX___availablequantity"));
        }

        [TestMethod]
        public void Outbound_With_Too_High_Quantity_Throws()
        {
            var item = SeedItem(available: 5);

            var ex = Assert.ThrowsExactly<InvalidPluginExecutionException>(
                () => Execute(MakeTransaction(item.Id, quantity: 10, Outbound)));

            StringAssert.Contains(ex.Message, "Not enough product in stock");
            StringAssert.Contains(ex.Message, "Available: 5");
            StringAssert.Contains(ex.Message, "requested: 10");
        }

        [TestMethod]
        public void Inbound_Is_Not_Validated()
        {
            var item = SeedItem(available: 0);

            // Inbound transactions add stock, so quantity above availability is fine.
            Execute(MakeTransaction(item.Id, quantity: 100, Inbound));
        }

        [TestMethod]
        public void Direct_Stock_Update_Is_Rejected()
        {
            var item = SeedItem(10);
            var target = new Entity("__PREFIX___warehouseitem", item.Id);
            target["__PREFIX___availablequantity"] = 999;
            var context = _context.GetDefaultPluginContext();
            context.MessageName = "Update";
            context.PrimaryEntityName = target.LogicalName;
            context.InputParameters["Target"] = target;
            Assert.ThrowsExactly<InvalidPluginExecutionException>(() =>
                _context.ExecutePluginWith(context, new ValidateWarehouseTransactionPlugin("", "")));
        }

        [TestMethod]
        public void Unchanged_Stock_Is_Removed_From_Catalogue_Updates()
        {
            var item = SeedItem(10);
            var target = new Entity("__PREFIX___warehouseitem", item.Id);
            target["__PREFIX___availablequantity"] = 10;
            target["__PREFIX___name"] = "Updated grocery name";
            var context = _context.GetDefaultPluginContext();
            context.MessageName = "Update";
            context.PrimaryEntityName = target.LogicalName;
            context.InputParameters["Target"] = target;
            _context.ExecutePluginWith(context, new ValidateWarehouseTransactionPlugin("", ""));
            Assert.IsFalse(target.Contains("__PREFIX___availablequantity"));
            Assert.AreEqual("Updated grocery name", target["__PREFIX___name"]);
        }

        [TestMethod]
        public void New_Item_Starts_At_Zero()
        {
            var target = new Entity("__PREFIX___warehouseitem", Guid.NewGuid());
            target["__PREFIX___availablequantity"] = 0;
            var context = _context.GetDefaultPluginContext();
            context.MessageName = "Create";
            context.PrimaryEntityName = target.LogicalName;
            context.InputParameters["Target"] = target;
            _context.ExecutePluginWith(context, new ValidateWarehouseTransactionPlugin("", ""));
        }
    }
}