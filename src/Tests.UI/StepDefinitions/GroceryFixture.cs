using System.Text.Json;
using Microsoft.Playwright;
using Tests.UI.Authentication;
using Tests.UI.Support;

namespace Tests.UI.StepDefinitions;

public sealed class GroceryFixture
{
    public string Id { get; }
    public string Name { get; }

    private GroceryFixture(string id, string name) { Id = id; Name = name; }

    private static async Task<IPage> OpenApiAsync(IBrowserContext context)
    {
        var page = await context.NewPageAsync();
        await page.GotoAsync($"{TestConfiguration.EnvironmentUrl.TrimEnd('/')}/main.aspx?appname={Uri.EscapeDataString(TestConfiguration.AppName)}");
        await page.WaitForFunctionAsync("() => !!window.Xrm?.WebApi?.createRecord");
        return page;
    }

    public static async Task<GroceryFixture> CreateAsync(IBrowserContext context, string label)
    {
        var name = $"BDD-{Guid.NewGuid():N} {label}";
        var page = await OpenApiAsync(context);
        try
        {
            var id = await page.EvaluateAsync<string>("""
                async name => (await Xrm.WebApi.createRecord("almlab_warehouseitem", {
                    "almlab_name": name,
                    "almlab_sku": name.substring(0, 36),
                    "almlab_availablequantity": 0,
                    "almlab_category": 100000002
                })).id
                """, name);
            return new GroceryFixture(id, name);
        }
        finally { await page.CloseAsync(); }
    }

    public async Task SeedAsync(IBrowserContext context, int quantity)
    {
        var page = await OpenApiAsync(context);
        try
        {
            await page.EvaluateAsync("""
                async args => {
                    await Xrm.WebApi.createRecord("almlab_warehousetransaction", {
                        "almlab_name": "BDD opening balance",
                        "almlab_quantity": args.quantity,
                        "almlab_transactiontype": 100000000,
                        "almlab_transactiondate": new Date().toISOString(),
                        "almlab_itemid@odata.bind": `/almlab_warehouseitems(${args.id})`
                    });
                }
                """, new { id = Id, quantity });
        }
        finally { await page.CloseAsync(); }
    }

    public async Task<JsonElement> ReadStateAsync(IBrowserContext context)
    {
        var page = await OpenApiAsync(context);
        try
        {
            return await page.EvaluateAsync<JsonElement>("""
                async id => {
                    const item = await Xrm.WebApi.retrieveRecord("almlab_warehouseitem", id, "?$select=almlab_availablequantity");
                    const movements = await Xrm.WebApi.retrieveMultipleRecords("almlab_warehousetransaction",
                        `?$select=almlab_warehousetransactionid&$filter=_almlab_itemid_value eq ${id}`);
                    return { quantity: item.almlab_availablequantity, movements: movements.entities.length };
                }
                """, Id);
        }
        finally { await page.CloseAsync(); }
    }

    public async Task DeleteAsync(IBrowser browser)
    {
        await using var context = await SignIn.CreateSignedInContextAsync(browser, "a warehouse manager");
        var page = await OpenApiAsync(context);
        // Only this scenario's item and its movements are selected. Deleting outbound
        // movements first restores the inbound stock before those opening balances go away.
        var records = await page.EvaluateAsync<JsonElement>("""
            async id => (await Xrm.WebApi.retrieveMultipleRecords("almlab_warehousetransaction",
                `?$select=almlab_warehousetransactionid,almlab_transactiontype&$filter=_almlab_itemid_value eq ${id}`)).entities
            """, Id);
        foreach (var record in records.EnumerateArray().OrderByDescending(x => x.GetProperty("almlab_transactiontype").GetInt32()))
        {
            var id = record.GetProperty("almlab_warehousetransactionid").GetString();
            await page.EvaluateAsync("id => Xrm.WebApi.deleteRecord('almlab_warehousetransaction', id)", id);
        }
        await page.EvaluateAsync("id => Xrm.WebApi.deleteRecord('almlab_warehouseitem', id)", Id);
    }
}
