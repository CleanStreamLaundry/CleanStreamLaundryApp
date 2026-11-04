import { describe, it, expect, vi, beforeEach } from "vitest";
import { LocationRepository } from "./LocationRepository";
import type { Location, Machine } from "../../interfaces/LocationService";
import { SupabaseClient } from "@supabase/supabase-js";

// ─── Mock useAuth ─────────────────────────────────────────────────────────────

const mockGetUserID = vi.fn();

vi.mock("../../di/container", () => ({
    useAuth: () => ({
        getUserID: mockGetUserID,
    }),
}));

// ─── Mock Data ────────────────────────────────────────────────────────────────

const mockUuid = "test-user-uuid";

const mockLocationIds = [{ location_id: 1 }, { location_id: 2 }];

const mockLocations: Location[] = [
    { id: 1, Name: "Location A", Address: "123 Main St", Latitude: 40.7128, Longitude: -74.006 },
    { id: 2, Name: "Location B", Address: "456 Elm St", Latitude: 34.0522, Longitude: -118.2437 },
];

const mockMachines: Machine[] = [
    { id: 1, Name: "Washer 1", Price: 2.5, Runtime: 30, Status: "Available", Location_ID: 1, Machine_type: "Washer", Weight_kg: 15 },
    { id: 2, Name: "Dryer 1", Price: 1.75, Runtime: 45, Status: "In Use", Location_ID: 1, Machine_type: "Dryer", Weight_kg: 25 },
];

const mockNewMachine: Machine = {
    id: 3,
    Name: "Washer 3",
    Price: 3.0,
    Runtime: 35,
    Status: "Available",
    Location_ID: 1,
    Machine_type: "Washer",
    Weight_kg: 12
};

const mockNewLocation: Location = {
    id: 3,
    Address: "789 Oak Ave",
    Name: "Location C",
    Latitude: 41.8781,
    Longitude: -87.6298,
};

// ─── Mock Client Factory ──────────────────────────────────────────────────────

const createMockClient = () => {
    const single = vi.fn();
    const inFn = vi.fn().mockReturnThis();
    const eqFn = vi.fn().mockReturnThis();
    const selectFn = vi.fn().mockReturnThis();
    const insertFn = vi.fn().mockReturnThis();

    const chainBase = {
        select: selectFn,
        eq: eqFn,
        in: inFn,
        insert: insertFn,
        single,
    };

    selectFn.mockReturnValue(chainBase);
    eqFn.mockReturnValue(chainBase);
    inFn.mockReturnValue(chainBase);
    insertFn.mockReturnValue(chainBase);

    const from = vi.fn().mockReturnValue(chainBase);

    const client = {
        from,
    } as unknown as SupabaseClient;

    return { client, from, selectFn, eqFn, inFn, insertFn, single };
};

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("LocationRepository", () => {

    beforeEach(() => {
        vi.clearAllMocks();
        mockGetUserID.mockResolvedValue(mockUuid);
    });

    // ── getLocations ──────────────────────────────────────────────────────────

    describe("getLocations", () => {
        it("returns locations for the authenticated user", async () => {
            const { client, from, inFn } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: vi.fn().mockResolvedValue({ data: mockLocationIds, error: null }),
            });

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                in: inFn.mockResolvedValue({ data: mockLocations, error: null }),
            });

            const repo = new LocationRepository(client);
            const result = await repo.getLocations();

            expect(result).toEqual(mockLocations);
        });

        it("throws when Location_to_Admin query fails", async () => {
            const { client, from } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: vi.fn().mockResolvedValue({ data: null, error: { message: "DB error" } }),
            });

            const repo = new LocationRepository(client);
            await expect(repo.getLocations()).rejects.toThrow("DB error");
        });

        it("throws when Locations query fails", async () => {
            const { client, from, inFn } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: vi.fn().mockResolvedValue({ data: mockLocationIds, error: null }),
            });

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                in: inFn.mockResolvedValue({ data: null, error: { message: "Locations fetch failed" } }),
            });

            const repo = new LocationRepository(client);
            await expect(repo.getLocations()).rejects.toThrow("Locations fetch failed");
        });

        it("calls getUserID to retrieve the current user", async () => {
            const { client, from, inFn } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: vi.fn().mockResolvedValue({ data: mockLocationIds, error: null }),
            });
            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                in: inFn.mockResolvedValue({ data: mockLocations, error: null }),
            });

            const repo = new LocationRepository(client);
            await repo.getLocations();

            expect(mockGetUserID).toHaveBeenCalledTimes(1);
        });

        // ── NEW: verify the extracted IDs are passed to .in() ─────────────────
        it("passes extracted location IDs to the Locations query", async () => {
            const { client, from, inFn } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: vi.fn().mockResolvedValue({ data: mockLocationIds, error: null }),
            });

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                in: inFn.mockResolvedValue({ data: mockLocations, error: null }),
            });

            const repo = new LocationRepository(client);
            await repo.getLocations();

            expect(inFn).toHaveBeenCalledWith("id", [1, 2]);
        });

        it("returns an empty array when the user has no linked locations", async () => {
            const { client, from, inFn } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: vi.fn().mockResolvedValue({ data: [], error: null }),
            });

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                in: inFn.mockResolvedValue({ data: [], error: null }),
            });

            const repo = new LocationRepository(client);
            const result = await repo.getLocations();

            expect(result).toEqual([]);
        });
    });

    // ── getMachines ───────────────────────────────────────────────────────────

    describe("getMachines", () => {
        it("selects only inventory fields while preserving nested configuration", async () => {
            const { client, from, eqFn, selectFn } = createMockClient();
            const config = { machine_id: 1, is_enabled: true };
            const data = [{ ...mockMachines[0], washer_size_rate_id: 7, cortina_machine_config: [config] }];
            from.mockReturnValueOnce({
                select: selectFn,
                eq: eqFn.mockResolvedValue({ data, error: null }),
            });
            selectFn.mockReturnValue({ eq: eqFn });

            const result = await new LocationRepository(client).getMachines("1");

            expect(selectFn).toHaveBeenCalledTimes(1);
            expect(selectFn).toHaveBeenCalledWith(
                "id, Name, Price, Runtime, Status, Location_ID, Machine_type, Weight_kg, washer_size_rate_id, cortina_machine_config(*)",
            );
            expect(eqFn).toHaveBeenCalledWith("Location_ID", 1);
            expect(result).toEqual([{ ...data[0], cortina_machine_config: config }]);
        });

        it("returns machines for a given location ID", async () => {
            const { client, from, eqFn } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: eqFn.mockResolvedValue({ data: mockMachines, error: null }),
            });

            const repo = new LocationRepository(client);
            const result = await repo.getMachines("1");

            expect(result).toEqual(mockMachines);
        });

        it("throws when Machines query fails", async () => {
            const { client, from, eqFn } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: eqFn.mockResolvedValue({ data: null, error: { message: "Machines fetch error" } }),
            });

            const repo = new LocationRepository(client);
            await expect(repo.getMachines("1")).rejects.toThrow("Machines fetch error");
        });

        it("passes the locationId as an integer to the query", async () => {
            const { client, from, eqFn } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: eqFn.mockResolvedValue({ data: mockMachines, error: null }),
            });

            const repo = new LocationRepository(client);
            await repo.getMachines("5");

            expect(eqFn).toHaveBeenCalledWith("Location_ID", 5);
        });

        it("returns an empty array when no machines exist for location", async () => {
            const { client, from, eqFn } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: eqFn.mockResolvedValue({ data: [], error: null }),
            });

            const repo = new LocationRepository(client);
            const result = await repo.getMachines("99");

            expect(result).toEqual([]);
        });
    });

    // ── addMachines ───────────────────────────────────────────────────────────

    describe("addMachines", () => {
        it("returns undefined on successful insert", async () => {
            const { client, from, insertFn } = createMockClient();

            from.mockReturnValueOnce({
                insert: insertFn.mockResolvedValue({ error: null }),
            });

            const repo = new LocationRepository(client);
            const result = await repo.addMachines(mockNewMachine);

            expect(result).toBeUndefined();
        });

        it("returns error message when insert fails", async () => {
            const { client, from, insertFn } = createMockClient();

            from.mockReturnValueOnce({
                insert: insertFn.mockResolvedValue({ error: { message: "Insert failed" } }),
            });

            const repo = new LocationRepository(client);
            const result = await repo.addMachines(mockNewMachine);

            expect(result).toBe("Insert failed");
        });

        it("inserts correct machine fields including Weight_kg", async () => {
            const { client, from, insertFn } = createMockClient();

            from.mockReturnValueOnce({
                insert: insertFn.mockResolvedValue({ error: null }),
            });

            const repo = new LocationRepository(client);
            await repo.addMachines(mockNewMachine);

            expect(insertFn).toHaveBeenCalledWith({
                Name: mockNewMachine.Name,
                Price: mockNewMachine.Price,
                Runtime: mockNewMachine.Runtime,
                Status: mockNewMachine.Status,
                Location_ID: mockNewMachine.Location_ID,
                Machine_type: mockNewMachine.Machine_type,
                Weight_kg: mockNewMachine.Weight_kg,
                washer_size_rate_id: null,
            });
        });
    });

    // ── addLocations ──────────────────────────────────────────────────────────

    describe("addLocations", () => {
        it("returns undefined on successful location insert", async () => {
            const { client, from, insertFn, single } = createMockClient();

            from.mockReturnValueOnce({
                insert: vi.fn().mockReturnValue({
                    select: vi.fn().mockReturnValue({
                        single: single.mockResolvedValue({ data: { id: 10 }, error: null }),
                    }),
                }),
            });

            from.mockReturnValueOnce({
                insert: insertFn.mockResolvedValue({ error: null }),
            });

            const repo = new LocationRepository(client);
            const result = await repo.addLocations(mockNewLocation);

            expect(result).toBeUndefined();
        });

        it("returns error message when location insert fails", async () => {
            const { client, from, single } = createMockClient();

            from.mockReturnValueOnce({
                insert: vi.fn().mockReturnValue({
                    select: vi.fn().mockReturnValue({
                        single: single.mockResolvedValue({
                            data: null,
                            error: { message: "Location insert error" },
                        }),
                    }),
                }),
            });

            const repo = new LocationRepository(client);
            const result = await repo.addLocations(mockNewLocation);

            expect(result).toBe("Location insert error");
        });

        it("calls addLocationToAdmin after successful insert", async () => {
            const { client, from, insertFn, single } = createMockClient();

            from.mockReturnValueOnce({
                insert: vi.fn().mockReturnValue({
                    select: vi.fn().mockReturnValue({
                        single: single.mockResolvedValue({ data: { id: 10 }, error: null }),
                    }),
                }),
            });

            from.mockReturnValueOnce({
                insert: insertFn.mockResolvedValue({ error: null }),
            });

            const repo = new LocationRepository(client);
            await repo.addLocations(mockNewLocation);

            expect(from).toHaveBeenCalledWith("Location_to_Admin");
        });

        it("does not call addLocationToAdmin when data is null", async () => {
            const { client, from, single } = createMockClient();

            from.mockReturnValueOnce({
                insert: vi.fn().mockReturnValue({
                    select: vi.fn().mockReturnValue({
                        single: single.mockResolvedValue({ data: null, error: null }),
                    }),
                }),
            });

            const repo = new LocationRepository(client);
            await repo.addLocations(mockNewLocation);

            expect(from).toHaveBeenCalledTimes(1);
        });

        it("inserts correct location fields", async () => {
            const { client, from, single } = createMockClient();
            const insertFn = vi.fn().mockReturnValue({
                select: vi.fn().mockReturnValue({
                    single: single.mockResolvedValue({ data: { id: 10 }, error: null }),
                }),
            });

            from.mockReturnValueOnce({ insert: insertFn });
            from.mockReturnValueOnce({
                insert: vi.fn().mockResolvedValue({ error: null }),
            });

            const repo = new LocationRepository(client);
            await repo.addLocations(mockNewLocation);

            expect(insertFn).toHaveBeenCalledWith({
                Address: mockNewLocation.Address,
                Name: mockNewLocation.Name,
                Latitude: mockNewLocation.Latitude,
                Longitude: mockNewLocation.Longitude,
            });
        });
    });

    // ── addLocationToAdmin ────────────────────────────────────────────────────

    describe("addLocationToAdmin", () => {
        it("inserts the correct locationId and userId", async () => {
            const { client, from, insertFn } = createMockClient();

            from.mockReturnValueOnce({
                insert: insertFn.mockResolvedValue({ error: null }),
            });

            const repo = new LocationRepository(client);
            await repo.addLocationToAdmin(42, mockUuid);

            expect(insertFn).toHaveBeenCalledWith({
                location_id: 42,
                user_id: mockUuid,
            });
        });

        it("throws when insert fails", async () => {
            const { client, from, insertFn } = createMockClient();

            from.mockReturnValueOnce({
                insert: insertFn.mockResolvedValue({ error: { message: "Admin link error" } }),
            });

            const repo = new LocationRepository(client);
            await expect(repo.addLocationToAdmin(42, mockUuid)).rejects.toThrow("Admin link error");
        });

        it("resolves without error on successful insert", async () => {
            const { client, from, insertFn } = createMockClient();

            from.mockReturnValueOnce({
                insert: insertFn.mockResolvedValue({ error: null }),
            });

            const repo = new LocationRepository(client);
            await expect(repo.addLocationToAdmin(1, mockUuid)).resolves.toBeUndefined();
        });
    });

    // ── fetchUserRole ─────────────────────────────────────────────────────────

    describe("fetchUserRole", () => {
        it("returns null when a query error accompanies privileged profile data", async () => {
            const { client, single } = createMockClient();
            single.mockResolvedValue({ data: { roles: "Owner" }, error: new Error("Role lookup failed") });

            const repo = new LocationRepository(client);

            expect(await repo.fetchUserRole()).toBeNull();
        });

        it("returns the role string when profile exists", async () => {
            const { client, from, single } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: vi.fn().mockReturnValue({
                    single: single.mockResolvedValue({ data: { roles: "Admin" }, error: null }),
                }),
            });

            const repo = new LocationRepository(client);
            const result = await repo.fetchUserRole();

            expect(result).toBe("Admin");
        });

        it("returns null when no profile data is returned", async () => {
            const { client, from, single } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: vi.fn().mockReturnValue({
                    single: single.mockResolvedValue({ data: null, error: { message: "Not found" } }),
                }),
            });

            const repo = new LocationRepository(client);
            const result = await repo.fetchUserRole();

            expect(result).toBeNull();
        });

        it("queries profiles table with the current user's ID", async () => {
            const { client, from, single, eqFn } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: eqFn.mockReturnValue({
                    single: single.mockResolvedValue({ data: { roles: "Owner" }, error: null }),
                }),
            });

            const repo = new LocationRepository(client);
            await repo.fetchUserRole();

            expect(from).toHaveBeenCalledWith("profiles");
            expect(eqFn).toHaveBeenCalledWith("id", mockUuid);
        });

        it("calls getUserID to get the current user", async () => {
            const { client, from, single } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: vi.fn().mockReturnValue({
                    single: single.mockResolvedValue({ data: { roles: "Admin" }, error: null }),
                }),
            });

            const repo = new LocationRepository(client);
            await repo.fetchUserRole();

            expect(mockGetUserID).toHaveBeenCalledTimes(1);
        });

        it("coerces a non-string role value to a string", async () => {
            const { client, from, single } = createMockClient();

            from.mockReturnValueOnce({
                select: vi.fn().mockReturnThis(),
                eq: vi.fn().mockReturnValue({
                    single: single.mockResolvedValue({ data: { roles: 2 }, error: null }),
                }),
            });

            const repo = new LocationRepository(client);
            const result = await repo.fetchUserRole();

            expect(typeof result).toBe("string");
            expect(result).toBe("2");
        });
    });

    describe("washer size rates", () => {
        it("loads rates for a location in capacity order", async () => {
            const rates = [{ id: 1, location_id: 4, size_label: "Large", capacity_kg: 18, price_cents: 425, is_active: true, review_required: false }];
            const order = vi.fn().mockResolvedValue({ data: rates, error: null });
            const eq = vi.fn().mockReturnValue({ order });
            const select = vi.fn().mockReturnValue({ eq });
            const from = vi.fn().mockReturnValue({ select });
            const repo = new LocationRepository({ from } as unknown as SupabaseClient);

            await expect(repo.getWasherSizeRates(4)).resolves.toEqual(rates);
            expect(eq).toHaveBeenCalledWith("location_id", 4);
            expect(order).toHaveBeenCalledWith("capacity_kg");
        });

        it("surfaces rate query errors", async () => {
            const order = vi.fn().mockResolvedValue({ data: null, error: { message: "Rate fetch failed" } });
            const client = { from: vi.fn().mockReturnValue({ select: vi.fn().mockReturnValue({ eq: vi.fn().mockReturnValue({ order }) }) }) } as unknown as SupabaseClient;
            await expect(new LocationRepository(client).getWasherSizeRates(4)).rejects.toThrow("Rate fetch failed");
        });
    });
});
