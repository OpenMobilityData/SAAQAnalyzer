# Quebec Vehicle Registration Data Schema Documentation

## Overview

This dataset represents vehicles authorized to circulate in Quebec as of December 31st each year. Each row represents one vehicle with its characteristics. The data is sourced from the Société de l'assurance automobile du Québec (SAAQ), which is the sole authority for issuing circulation rights in Quebec.

## Dataset Structure

### Core Identification Variables

| Variable | Type | Length | Description |
|----------|------|--------|-------------|
| **AN** | Numeric | 8 | Year of the vehicle circulation portrait (year for which a vehicle is authorized to circulate, as of December 31st) |
| **NOSEQ_VEH** | Alphanumeric | 15 | Sequential number uniquely identifying a vehicle. Format: `AN_sequential_number` |

### Vehicle Classification

| Variable | Type | Length | Description |
|----------|------|--------|-------------|
| **CLAS** | Alphanumeric | 3 | Code identifying the vehicle type and its usage type |

#### CLAS Values by Usage Category

##### Personal Use (Promenade)
- **PAU**: Automobile or light truck
- **PMC**: Motorcycle
- **PCY**: Moped
- **PHM**: Motorhome

##### Institutional, Professional or Commercial Use
- **CAU**: Automobile or light truck
- **CMC**: Motorcycle
- **CCY**: Moped
- **CHM**: Motorhome
- **TTA**: Taxi
- **TAB**: Bus
- **TAS**: School bus
- **BCA**: Truck or road tractor
- **CVO**: Tool vehicle
- **COT**: Others (tow trucks, hearses, ambulances, driving school vehicles, movable plates)

##### Restricted Circulation (max 70 km/h zones)
- **RAU**: Automobile or light truck
- **RMC**: Motorcycle (1980 or earlier, preserved/restored)
- **RCY**: Moped
- **RHM**: Motorhome
- **RAB**: Bus
- **RCA**: Truck or road tractor
- **RMN**: Snowmobile
- **ROT**: Others

##### Off-Road Use
- **HAU**: Automobile or light truck
- **HCY**: Moped
- **HAB**: Bus
- **HCA**: Truck or road tractor
- **HMN**: Snowmobile
- **HVT**: All-terrain vehicle (ATV, quad, off-road motorcycle, 3-wheel off-road)
- **HVO**: Tool vehicle
- **HOT**: Others

### Vehicle Type Category

| Variable | Type | Length | Description |
|----------|------|--------|-------------|
| **TYP_VEH_CATEG_USA** | Alphanumeric | 2 | Physical configuration code of vehicle with circulation rights |

#### TYP_VEH_CATEG_USA Values
- **AB**: Bus
- **AT**: Dealer Plates (Auto/Temporary - for movable plates)
- **AU**: Automobile or light truck
- **CA**: Truck or road tractor
- **CY**: Moped
- **HM**: Motorhome
- **MC**: Motorcycle
- **MN**: Snowmobile
- **NV**: Other off-road vehicles (not MN, VT, or VO - vehicles lacking equipment required by law for public roads)
- **SN**: Snow blower
- **UK**: Unknown (user-assigned in regularization system when vehicle type cannot be determined)
- **VO**: Tool vehicle
- **VT**: All-terrain vehicle

### Vehicle Characteristics

| Variable | Type | Length | Description |
|----------|------|--------|-------------|
| **MARQ_VEH** | Alphanumeric | 5 | Vehicle brand code recognized by manufacturer. Special values: AMOVI (movable plate), ARTIS (artisanal), SOUFF (snow blower) |
| **MODEL_VEH** | Alphanumeric | 5 | Vehicle model code recognized by manufacturer. ARTIS = artisanal vehicle |
| **ANNEE_MOD** | Numeric | 8 | Model year as designated by manufacturer. For modified vehicles, indicates oldest component year |
| **MASSE_NETTE** | Numeric | 8 | Net mass in kilograms from manufacturer or weight revision |

### Engine Specifications

| Variable | Type | Length | Description | Values |
|----------|------|--------|-------------|---------|
| **NB_CYL** | Alphanumeric | 1 | Number of cylinders | 1-8 (one to eight cylinders), 9 (other/more than 8) |
| **CYL_VEH** | Numeric | 8 | Engine capacity in cubic centimeters (cm³). Not available for tool vehicles and snowmobiles |

### Truck-Specific Information

| Variable | Type | Length | Description | Values |
|----------|------|--------|-------------|---------|
| **NB_ESIEU_MAX** | Alphanumeric | 1 | Maximum number of axles (vehicle + trailers). Only for BCA class | 2-5 (two to five axles), 6 (six or more axles) |

### Vehicle Appearance

| Variable | Type | Length | Description | Values |
|----------|------|--------|-------------|---------|
| **COUL_ORIG** | Alphanumeric | 3 | Original vehicle color | See color codes below |

#### Color Codes (COUL_ORIG)
- ARG: Silver
- BEI: Beige
- BLA: White
- BLE: Blue
- BRO: Bronze
- BRU: Brown
- CHA: Champagne
- CUI: Copper
- GRI: Grey
- JAU: Yellow
- KAK: Khaki
- MAR: Maroon
- MAU: Mauve
- MTL: Multicolor
- NOI: Black
- OR/ORA: Orange
- ROS: Pink
- ROU: Red
- VER: Green
- VIO: Violet
- blanc: Not specified

### Fuel Type

| Variable | Type | Length | Description | Values |
|----------|------|--------|-------------|---------|
| **TYP_CARBU** | Alphanumeric | 1 | Fuel type or propulsion mode. Not available before 2017 | See fuel codes below |

#### Fuel Type Codes (TYP_CARBU)
- A: Other
- C: Hydrogen
- D: Diesel
- E: Gasoline
- H: Hybrid
- L: Electricity
- M: Methanol
- N: Natural gas
- P: Propane
- S: Non-propelled
- T: Ethanol
- W: Plug-in hybrid
- blanc: Not specified

### Owner Geographic Information

| Variable | Type | Length | Description |
|----------|------|--------|-------------|
| **REG_ADM** | Alphanumeric | 34 | Administrative region of vehicle owner's residence |
| **MRC** | Alphanumeric | 36 | Regional County Municipality of owner's residence. Blank = Outside Quebec or not specified |
| **CG_FIXE** | Alphanumeric | 5 | Geographic code of owner's municipality. Blank = Outside Quebec or not specified |

#### Administrative Regions (REG_ADM)
Same as driver's license data:
- Bas-Saint-Laurent (01)
- Saguenay―Lac-Saint-Jean (02)
- Capitale-Nationale (03)
- Mauricie (04)
- Estrie (05)
- Montréal (06)
- Outaouais (07)
- Abitibi-Témiscamingue (08)
- Côte-Nord (09)
- Nord-du-Québec (10)
- Gaspésie―Îles-de-la-Madeleine (11)
- Chaudière-Appalaches (12)
- Laval (13)
- Lanaudière (14)
- Laurentides (15)
- Montérégie (16)
- Centre-du-Québec (17)
- blanc: Outside Quebec or not specified

## Vehicle Categories Detailed Definitions

### Automobiles and Light Trucks (AU/PAU/CAU/etc.)
- Vehicles of 3,000 kg or less designed primarily for passenger transport, not built on truck chassis
- Vans, pickup trucks, or all-purpose vehicles (4x4) of 4,000 kg or less

### Motorcycles (MC/PMC/CMC/etc.)
- Two or three-wheeled road vehicles with at least one characteristic differing from mopeds

### Mopeds (CY/PCY/CCY/etc.)
- Two or three wheels with engine ≤50 cm³ and automatic transmission
- Three wheels designed for disabled persons recognized as moped by SAAQ regulation
- Two or three wheel vehicles limited to 70 km/h with electric motor meeting Transport Canada standards

### Buses (TAB)
- Urban public buses
- Intercity public buses
- Buses regularly transporting people without remuneration

### School Buses (TAS)
- Buses or minibuses assigned to student transportation

### Trucks and Road Tractors (BCA)
- Road vehicles over 3,000 kg designed specifically for freight transport
- Registered according to maximum number of axles (tractor unit + all attached trailers)

### Tool Vehicles (CVO)
- Road vehicles designed primarily for specific work with appropriate tooling
- Vehicles used exclusively for snow removal

### Taxis (TTA)
- Serving an agglomeration
- Serving a region
- Specialized transport or limousine requiring special permit from Quebec Transport Commission

## Important Notes

### Data Snapshot
- Data represents vehicles authorized to circulate as of December 31st each year
- Vehicle age = number of years from model year to year AN
- Vehicles with model year ≥ AN are considered less than one year old

### Special Cases
- Personal use includes individuals, multiple co-owners, and personal use purposes
- Institutional/commercial use includes corporations, governments, public organizations, agricultural producers, self-employed professionals
- Also includes non-Canadian citizens in specific diplomatic or international aviation roles

### Additional Resources
- Vehicle registration information: https://saaq.gouv.qc.ca/immatriculation/immatriculer-vehicule/
- Municipality codes: www.mamrot.gouv.qc.ca