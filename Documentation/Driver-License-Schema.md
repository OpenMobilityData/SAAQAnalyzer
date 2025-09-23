# Quebec Driver's License Data Schema Documentation

## Overview

This dataset represents driver's license holders in Quebec as of June 1st each year. Each row represents one license holder with their demographic information, license types, classes, and driving experience. The data is sourced from the Société de l'assurance automobile du Québec (SAAQ), which is the sole authority for issuing driver's licenses in Quebec.

## Dataset Structure

### Core Identification Variables

| Variable | Type | Length | Description |
|----------|------|--------|-------------|
| **AN** | Numeric | 4 | Year for which a license privilege is held (YYYY format), as of June 1st |
| **NOSEQ_TITUL** | Alphanumeric | 200 | Sequential number identifying a license holder. Format: `AN_sequential_number` |

### Demographic Variables

| Variable | Type | Length | Description | Values |
|----------|------|--------|-------------|---------|
| **AGE_1ER_JUIN** | Alphanumeric | 15 | Age group of the license holder on June 1st of year AN | Age ranges |
| **SEXE** | Alphanumeric | 1 | Sex of the license holder | F (Female), M (Male) |

### Geographic Variables

| Variable | Type | Length | Description |
|----------|------|--------|-------------|
| **MRC** | Alphanumeric | 36 | Regional County Municipality where the license holder lives (calculated from municipality's geographic code) |
| **REG_ADM** | Alphanumeric | 40 | Administrative region of Quebec where the license holder lives |

#### Administrative Regions (REG_ADM)
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

### License Type

| Variable | Type | Length | Description | Values |
|----------|------|--------|-------------|---------|
| **TYPE_PERMIS** | Alphanumeric | 10 | Type of license held as of June 1st | APPRENTI, PROBATOIRE, RÉGULIER |

#### License Type Values
- **APPRENTI**: Learner's permit for passenger vehicle or motorcycle
- **PROBATOIRE**: Probationary license (any class)
- **RÉGULIER**: Regular license (any class)

### License Indicator Variables

All indicator variables are Alphanumeric, 1 character length, with possible values: **OUI** (Yes) or **NON** (No)

#### Learner's Permit Indicators
| Variable | Description |
|----------|-------------|
| **IND_PERMISAPPRENTI_123** | Indicates learner's permit for class 1, 2, or 3 |
| **IND_PERMISAPPRENTI_5** | Indicates learner's permit for class 5 |
| **IND_PERMISAPPRENTI_6A6R** | Indicates learner's permit for class 6A or 6R |

#### Driver's License Indicators
| Variable | Description |
|----------|-------------|
| **IND_PERMISCONDUIRE_1234** | Indicates driver's license for class 1, 2, 3, 4A, 4B, or 4C |
| **IND_PERMISCONDUIRE_5** | Indicates driver's license for class 5 |
| **IND_PERMISCONDUIRE_6ABCE** | Indicates driver's license for class 6A, 6B, 6C, or 6E |
| **IND_PERMISCONDUIRE_6D** | Indicates driver's license for class 6D |
| **IND_PERMISCONDUIRE_8** | Indicates driver's license for class 8 |

#### Probationary Status
| Variable | Description |
|----------|-------------|
| **IND_PROBATOIRE** | Indicates probationary license (any class) |

### Experience Variables

All experience variables are Alphanumeric, 14 characters length, representing years of experience.

| Variable | Description | Notes |
|----------|-------------|-------|
| **EXPERIENCE_1234** | Years of driving experience with class 1, 2, 3, 4A, 4B, or 4C vehicles | Simultaneous possession of multiple classes counted only once |
| **EXPERIENCE_5** | Years of driving experience with class 5 vehicles | - |
| **EXPERIENCE_6ABCE** | Years of driving experience with class 6A, 6B, 6C, or 6E vehicles | Simultaneous possession of multiple classes counted only once |
| **EXPERIENCE_GLOBALE** | Total years of driving experience with any license class | If EXPERIENCE_GLOBALE > EXPERIENCE_5, indicates holder had class 6D before class 5 |

## License Classes Reference

### Heavy Vehicles
- **Class 1**: Tractor-trailer (truck with no cargo space, equipped permanently with a coupling device)
- **Class 2**: Bus (designed for transportation of more than 24 passengers at once)
- **Class 3**: Truck (3+ axles, or 2 axles with net mass ≥4,500 kg)

### Commercial Vehicles
- **Class 4A**: Emergency vehicle
- **Class 4B**: Minibus/bus (24 passengers or less)
- **Class 4C**: Taxi (requires additional taxi driver permit from SAAQ or Montreal taxi bureau)

### Personal Vehicles
- **Class 5**: Passenger vehicle, motorhome, tool vehicle, service vehicle (tow truck), 3-wheel vehicles (T-Rex/Slingshot type)

### Motorcycles
- **Class 6A**: Motorcycle (all engine sizes)
- **Class 6B**: Motorcycle (≤400 cm³ engine)
- **Class 6C**: Motorcycle (≤125 cm³ engine)
- **Class 6D**: Moped
- **Class 6E**: 3-wheel motorcycle (requires class 5 + 6E with 7-hour training, OR any class 6A/6B/6C)

### Agricultural
- **Class 8**: Farm tractor

## Important Notes

### License Progression
1. **Learner's Permit**: Initial document allowing driving with a monitor or accompanying driver at all times
2. **Probationary License**: 24-month period after learner's permit with stricter rules (fewer demerit points, zero alcohol)
3. **Regular License**: Obtained after completing the 24-month probationary period

### Key Points
- Data snapshot taken on June 1st of each year
- Each person typically has only one probationary period in their lifetime (usually with class 5 or 6A)
- If probation was already completed, holders obtain regular license immediately after learner's permit
- The NOSEQ_TITUL field uniquely identifies each license holder in the dataset

### Data Usage
- TYPE_PERMIS "APPRENTI" value allows recreation of Table 85 from the SAAQ statistical dossier
- TYPE_PERMIS "PROBATOIRE" and "RÉGULIER" values allow recreation of Tables 63-80 from the SAAQ statistical dossier

### Additional Resources
- License information: https://saaq.gouv.qc.ca/permis-de-conduire/obtenir-permis/
- Municipality codes: www.mamrot.gouv.qc.ca