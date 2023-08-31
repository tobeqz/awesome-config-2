const BATTERY_PATH: &'static str = "/sys/class/power_supply/BAT0/";

fn read_battery_file(file: &str, strip_last_char: bool) -> String {
    use std::fs::File;
    use std::io::prelude::*;
    let mut full_path = String::from(BATTERY_PATH);
    full_path.push_str(file);

    let mut contents = String::new();
    let mut file = File::open(full_path).expect("Unable to open battery file");
    file.read_to_string(&mut contents)
        .expect("Unable to read file");

    if strip_last_char {
        contents.pop();
    }

    contents
}

fn parse_int(string: String) -> i32 {
    string.parse::<i32>().expect("Unable to parse int")
}

fn main() {
    let energy_full = parse_int(read_battery_file("energy_full", true));
    let energy_now = parse_int(read_battery_file("energy_now", true));
    let power_now = parse_int(read_battery_file("power_now", true));

    let percentage = ((energy_now as f32) / (energy_full as f32) * 100.0).round();

    let status = read_battery_file("status", true);
    let status_short: &str;

    let time_remaining = match status.as_str() {
        "Charging" => {
            let remaining_energy = energy_full - energy_now;
            status_short = "Charging";
            (remaining_energy as f32) / (power_now as f32)
        }
        "Discharging" => {
            let remaining_energy = energy_now;
            status_short = "Discharging";
            (remaining_energy as f32) / (power_now as f32)
        },
        "Not charging" => {
            status_short = "NotCharging";
            0.0
        },
        "Full" => {
            status_short = "Full";
            0.0
        }
        _ => panic!("Unknown battery status: {}", status),
    };

    let time_remaining_split: Vec<String> = time_remaining
        .to_string()
        .split(".")
        .map(|str_part| String::from(str_part))
        .collect();
    let hours_part = &time_remaining_split[0];
    let frac_part = match time_remaining_split.get(1) {
        Some(s) => &s[0..1],
        None => "0"
    };
    let time_remaining = format!("{}.{}", hours_part, frac_part);

    println!("{} {} {}", percentage, status_short, time_remaining);
}
