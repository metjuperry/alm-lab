using System;
using System.Collections.Generic;
using System.ServiceModel;
using FakeItEasy;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Messages;
using Microsoft.Xrm.Sdk.Query;
using Plugins.Warehouse;

namespace Tests.Plugins
{
    [TestClass]
    public class SubtractQuantityPluginTests
    {
        private readonly Dictionary<Guid, Entity> _items = new();
        private readonly IOrganizationService _service = A.Fake<IOrganizationService>();
        private int _writes;
        private const int Inbound = 100000000;
        private const int Outbound = 100000001;

        private sealed class TestPlugin : SubtractQuantityPlugin
        {
            internal TestPlugin() : base("", "") { }
            internal void Run(ILocalPluginContext context) => ExecuteDataversePlugin(context);
        }

        public SubtractQuantityPluginTests()
        {
            // FakeXrmEasy's CRUD store drops RowVersion. This service double verifies the
            // optimistic-concurrency request contract; live rollback remains an integration test.
            A.CallTo(() => _service.Retrieve(A<string>._, A<Guid>._, A<ColumnSet>._))
                .ReturnsLazily((string _, Guid id, ColumnSet _) =>
                {
                    var item = _items[id];
                    return new Entity(item.LogicalName, id)
                    {
                        RowVersion = item.RowVersion,
                        ["almlab_availablequantity"] = item["almlab_availablequantity"]
                    };
                });
            A.CallTo(() => _service.Execute(A<OrganizationRequest>._))
                .ReturnsLazily((OrganizationRequest request) =>
                {
                    var update = (UpdateRequest)request;
                    Assert.AreEqual(ConcurrencyBehavior.IfRowVersionMatches, update.ConcurrencyBehavior);
                    Assert.AreEqual(_items[update.Target.Id].RowVersion, update.Target.RowVersion);
                    _items[update.Target.Id]["almlab_availablequantity"] = update.Target["almlab_availablequantity"];
                    _writes++;
                    return new UpdateResponse();
                });
        }

        private Entity Item(int available)
        {
            var item = new Entity("almlab_warehouseitem", Guid.NewGuid()) { RowVersion = "1" };
            item["almlab_availablequantity"] = available;
            _items.Add(item.Id, item);
            return item;
        }

        private static Entity Movement(Entity item, int quantity, int type) =>
            new("almlab_warehousetransaction", Guid.NewGuid())
            {
                ["almlab_itemid"] = item.ToEntityReference(),
                ["almlab_quantity"] = quantity,
                ["almlab_transactiontype"] = new OptionSetValue(type)
            };

        private void Execute(string message, object target, Entity? before = null, bool transactional = true)
        {
            var execution = A.Fake<IPluginExecutionContext>();
            A.CallTo(() => execution.PrimaryEntityName).Returns("almlab_warehousetransaction");
            A.CallTo(() => execution.MessageName).Returns(message);
            A.CallTo(() => execution.IsInTransaction).Returns(transactional);
            A.CallTo(() => execution.InputParameters).Returns(new ParameterCollection { ["Target"] = target });
            A.CallTo(() => execution.SharedVariables).Returns(new ParameterCollection());
            var images = new EntityImageCollection();
            if (before != null) images.Add("Before", before);
            A.CallTo(() => execution.PreEntityImages).Returns(images);
            var factory = A.Fake<IOrganizationServiceFactory>();
            A.CallTo(() => factory.CreateOrganizationService(A<Guid?>._)).Returns(_service);
            var context = A.Fake<ILocalPluginContext>();
            A.CallTo(() => context.PluginExecutionContext).Returns(execution);
            A.CallTo(() => context.OrgSvcFactory).Returns(factory);
            new TestPlugin().Run(context);
        }

        private static int Balance(Entity item) => item.GetAttributeValue<int>("almlab_availablequantity");

        [TestMethod]
        [DataRow(Inbound, 15)]
        [DataRow(Outbound, 5)]
        public void Create_Applies_Signed_Effect(int type, int expected)
        {
            var item = Item(10);
            Execute("Create", Movement(item, 5, type));
            Assert.AreEqual(expected, Balance(item));
        }

        [TestMethod]
        [DataRow(0)]
        [DataRow(-1)]
        public void Rejects_Nonpositive_Quantity(int quantity)
        {
            var item = Item(10);
            Assert.ThrowsExactly<InvalidPluginExecutionException>(() => Execute("Create", Movement(item, quantity, Inbound)));
            Assert.AreEqual(0, _writes);
        }

        [TestMethod]
        public void Sparse_Update_Applies_Only_Difference()
        {
            var item = Item(7);
            var before = Movement(item, 3, Outbound);
            Execute("Update", new Entity(before.LogicalName, before.Id) { ["almlab_quantity"] = 5 }, before);
            Assert.AreEqual(5, Balance(item));
        }

        [TestMethod]
        public void Type_Change_Reverses_Old_Effect()
        {
            var item = Item(7);
            var before = Movement(item, 3, Outbound);
            Execute("Update", new Entity(before.LogicalName, before.Id) { ["almlab_transactiontype"] = new OptionSetValue(Inbound) }, before);
            Assert.AreEqual(13, Balance(item));
        }

        [TestMethod]
        public void Item_Change_Updates_Both_Balances()
        {
            var oldItem = Item(7);
            var newItem = Item(20);
            var before = Movement(oldItem, 3, Outbound);
            Execute("Update", new Entity(before.LogicalName, before.Id) { ["almlab_itemid"] = newItem.ToEntityReference() }, before);
            Assert.AreEqual(10, Balance(oldItem));
            Assert.AreEqual(17, Balance(newItem));
        }

        [TestMethod]
        public void Nonstock_Update_Does_Not_Write()
        {
            var item = Item(7);
            var before = Movement(item, 3, Outbound);
            Execute("Update", new Entity(before.LogicalName, before.Id) { ["almlab_notes"] = "Corrected" }, before);
            Assert.AreEqual(0, _writes);
        }

        [TestMethod]
        public void Delete_Outbound_Restores_Stock()
        {
            var item = Item(7);
            var before = Movement(item, 3, Outbound);
            Execute("Delete", before.ToEntityReference(), before);
            Assert.AreEqual(10, Balance(item));
        }

        [TestMethod]
        public void Delete_Consumed_Inbound_Is_Rejected_Before_Writing()
        {
            var item = Item(2);
            var before = Movement(item, 5, Inbound);
            Assert.ThrowsExactly<InvalidPluginExecutionException>(() => Execute("Delete", before.ToEntityReference(), before));
            Assert.AreEqual(0, _writes);
        }

        [TestMethod]
        public void Cross_Item_Rejection_Does_Not_Write_Either_Item()
        {
            var oldItem = Item(7);
            var newItem = Item(1);
            var before = Movement(oldItem, 3, Outbound);
            var target = new Entity(before.LogicalName, before.Id) { ["almlab_itemid"] = newItem.ToEntityReference() };
            Assert.ThrowsExactly<InvalidPluginExecutionException>(() => Execute("Update", target, before));
            Assert.AreEqual(0, _writes);
        }

        [TestMethod]
        public void Missing_Preimage_Is_Actionable()
        {
            var item = Item(10);
            var error = Assert.ThrowsExactly<InvalidPluginExecutionException>(() => Execute("Update", Movement(item, 1, Inbound)));
            StringAssert.Contains(error.Message, "Before pre-image");
        }

        [TestMethod]
        public void Concurrency_Conflict_Asks_User_To_Retry()
        {
            var item = Item(10);
            A.CallTo(() => _service.Execute(A<OrganizationRequest>._)).Throws(
                new FaultException<OrganizationServiceFault>(new OrganizationServiceFault { ErrorCode = -2147088254 }));
            var error = Assert.ThrowsExactly<InvalidPluginExecutionException>(() => Execute("Create", Movement(item, 1, Outbound)));
            StringAssert.Contains(error.Message, "retry");
        }

        [TestMethod]
        public void Refuses_Nontransactional_Registration()
        {
            var item = Item(10);
            Assert.ThrowsExactly<InvalidPluginExecutionException>(() => Execute("Create", Movement(item, 1, Inbound), transactional: false));
            Assert.AreEqual(0, _writes);
        }
    }
}
