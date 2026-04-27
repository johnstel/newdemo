/**
 * A single synthetic weather observation document.
 * Partition key: cityId (value like "city-seattle-wa")
 * All fields are public-style, non-sensitive, generated locally.
 */
export interface WeatherObservation {
    id: string;
    cityId: string;
    tenantId: string;
    workloadId: string;
    schemaVersion: string;
    documentType: string;
    region: string;
    city: string;
    state: string;
    country: string;
    deviceId: string;
    source: string;
    observedAt: string;
    ingestedAt: string;
    metrics: WeatherMetrics;
}
export interface WeatherMetrics {
    temperatureCelsius: number;
    humidityPercent: number;
    windSpeedKph: number;
    windDirectionDeg: number;
    pressureHpa: number;
    precipitationMm: number;
    cloudCoverPercent: number;
    visibilityKm: number;
    uvIndex: number;
    condition: string;
}
/** Station catalog — public US cities used for demo variety */
declare const STATIONS: ReadonlyArray<{
    cityId: string;
    city: string;
    state: string;
    region: string;
    deviceId: string;
}>;
/**
 * Generate one synthetic weather observation record.
 * The station is chosen round-robin by index to distribute partition load evenly.
 */
export declare function generateWeatherObservation(stationIndex: number): WeatherObservation;
export { STATIONS };
//# sourceMappingURL=data-generator.d.ts.map