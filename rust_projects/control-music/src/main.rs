use std::time::Duration;

use color_eyre::eyre::eyre;
use color_eyre::{Help, Result};
use dbus::blocking::Connection;
use player::Player;
use clap::Parser;

mod player;
mod player_selection;
use player_selection::*;

#[derive(Parser)]
#[command(name = "control-music")]
#[command(bin_name = "control-music")]
enum Cli {
    #[command(about="Start playing media")]
    Play,

    #[command(about="Stop playing media")]
    Pause,

    #[command(about="Start/Stop playing media")]
    PlayPause,

    #[command(about="Skip the current song")]
    Next,

    #[command(about="Play the previous song")]
    Prev,

    #[command(about="Get the length of the current track")]
    GetLength,

    #[command(about="Print the status of the player (Paused/Playing)")]
    GetStatus,

    #[command(about="Get the current position in microseconds")]
    GetPosition,

    #[command(about="Print current song metadata")]
    GetMetadata,

    #[command(about="Get a JSON object containing all data")]
    AllData
}

fn main() -> Result<()> {
    color_eyre::install()?;

    let args = Cli::parse();

    let conn = Connection::new_session().note("Failed to initialize DBus session")?;
    let player_interfaces = get_player_interfaces(&conn).note("Failed to list media players")?;

    if player_interfaces.len() == 0 {
        return Err(eyre!("No players found"));
    }

    let relevant_player = get_most_relevant_player(&conn, &player_interfaces)
        .note("Failed to get most relevant player")?;
    save_relevant_player(&relevant_player).note("Failed to save the relevant player")?;

    let proxy = conn.with_proxy(
        relevant_player,
        "/org/mpris/MediaPlayer2",
        Duration::from_secs(1),
    );

    let player = Player::new(proxy);

    use Cli::*;
    match args {
        Play => player.play()?,
        Pause => player.pause()?,
        PlayPause => player.play_pause()?,
        Next => player.next()?,
        Prev => player.prev()?,
        GetLength => println!("{}", player.get_length()?),
        GetStatus => println!("{}", player.get_status()?),
        GetPosition => println!("{}", player.get_position()?),
        GetMetadata => println!("{}", player.get_metadata()?),
        AllData => println!("{}", player.get_all_data_json()?)
    }

    Ok(())
}
