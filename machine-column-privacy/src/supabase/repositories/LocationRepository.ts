import { SupabaseClient } from "@supabase/supabase-js";
import type { CortinaMachineConfig, LocationService, Location, Machine, WasherSizeRate } from "../../interfaces/LocationService";
import { useAuth as getAuthService } from "../../di/container";

export class LocationRepository implements LocationService {
    constructor(private client: SupabaseClient) { }
    
    getLocations = async (): Promise<Location[]> => {
        const authService = getAuthService()
        const Uuid = await authService.getUserID()
        
        const { data: adminData, error: adminError } = await this.client
            .from("Location_to_Admin")
            .select("location_id")
            .eq("user_id", Uuid?.toString());
        if (adminError) {
            console.error(adminError);
            throw new Error(adminError.message);
        }

        const locationIDs = adminData.map((row) => row.location_id);

        const { data: locations, error: locationsError } = await this.client
            .from("Locations")
            .select("*")
            .in("id", locationIDs);

        if (locationsError) {
            console.error(locationsError);
            throw new Error(locationsError.message);
        }
        return locations as Location[];
    };

    getMachines = async (locationId: string): Promise<Machine[]> => {
    const { data: getMachines, error: getMachinesError } = await this.client
        .from("Machines")
        .select("id, Name, Price, Runtime, Status, Location_ID, Machine_type, Weight_kg, washer_size_rate_id, cortina_machine_config(*)")
        .eq("Location_ID", parseInt(locationId));

    if (getMachinesError) {
        console.error(getMachinesError);
        throw new Error(getMachinesError.message);
    }

    return (getMachines ?? []).map((machine) => ({
        ...machine,
        cortina_machine_config: Array.isArray(machine.cortina_machine_config)
            ? machine.cortina_machine_config[0] ?? null
            : machine.cortina_machine_config,
    })) as Machine[];
};

    getWasherSizeRates = async (locationId: number): Promise<WasherSizeRate[]> => {
        const { data, error } = await this.client
            .from("washer_size_rates")
            .select("*")
            .eq("location_id", locationId)
            .order("capacity_kg");
        if (error) throw new Error(error.message);
        return data as WasherSizeRate[];
    }

    saveWasherSizeRate = async (rate: WasherSizeRate): Promise<void|string> => {
        const values = {
            location_id: rate.location_id,
            size_label: rate.size_label.trim(),
            capacity_kg: rate.capacity_kg,
            price_cents: rate.price_cents,
            is_active: rate.is_active,
            review_required: rate.review_required,
        };
        const query = rate.id
            ? this.client.from("washer_size_rates").update(values).eq("id", rate.id)
            : this.client.from("washer_size_rates").insert(values);
        const { error } = await query;
        return error?.message;
    }

    saveCortinaConfig = async (config: CortinaMachineConfig): Promise<void|string> => {
        const { error } = await this.client.from("cortina_machine_config").update({
            nayax_terminal_id: config.nayax_terminal_id,
            nayax_uniqr: config.nayax_uniqr,
            pulse_line_number: config.pulse_line_number,
            product_codes: config.product_codes ?? null,
            environment: config.environment,
            is_enabled: config.is_enabled,
            review_required: config.review_required,
        }).eq("machine_id", config.machine_id);
        return error?.message;
    }

    addMachines = async (machine: Machine): Promise<void|string>  => {
        const { error: addMachinesError } = await this.client
        .from("Machines")
        .insert({
            Name: machine.Name, 
            Price: machine.Price, 
            Runtime: machine.Runtime, 
            Status: machine.Status, 
            Location_ID: machine.Location_ID, 
            Machine_type: machine.Machine_type,
            Weight_kg: machine.Weight_kg,
            washer_size_rate_id: machine.washer_size_rate_id ?? null});

        if (addMachinesError) {
        console.error(addMachinesError);
        return(addMachinesError?.message)
        }
    }

    addLocations = async (location: Location): Promise<void|string>  => {
        const authService = getAuthService()
        const Uuid = await authService.getUserID()
        const { data, error: addLocationsError } = await this.client
        .from("Locations")
        .insert({
            Address: location.Address,
            Name: location.Name,
            Latitude: location.Latitude,
            Longitude: location.Longitude,
        })
        .select("id")
        .single();
        if (addLocationsError) {
        console.error(addLocationsError);
        return(addLocationsError.message)
        }

        if (data != null && Uuid != null) {
        await this.addLocationToAdmin(data.id, Uuid)
        }
    }

    addLocationToAdmin = async (locationId:number ,uid:string): Promise<void> =>{
        const {error: addLocationToAdminError } = await this.client
        .from("Location_to_Admin")
        .insert({
            location_id: locationId,
            user_id: uid
        });

        if (addLocationToAdminError) {
        console.error(addLocationToAdminError);
        throw new Error(addLocationToAdminError.message);
        }
    }

    fetchUserRole = async (): Promise<string | null> => {
        const authService = getAuthService()
        const userId = await authService.getUserID();
        const {data,error} = await this.client
              .from('profiles')
              .select("roles")
              .eq('id', userId)
              .single();

          if (error) return null;
  
          if(data != null) {
              return data.roles.toString()
          }else{
            return null
          }
      }

    deleteMachine = async (machineID: number): Promise<void> => {
        const {error: deleteMachineError} = await this.client
        .from('Machines')
        .delete()
        .eq('id', machineID)

        if (deleteMachineError) {
        console.error(deleteMachineError);
        throw new Error(deleteMachineError.message);
        }
      }
}
