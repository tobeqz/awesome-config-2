use std::{time::Duration, path::PathBuf, fs, io};

use dbus::blocking::{Connection, stdintf::org_freedesktop_dbus::Properties};
use color_eyre::{Result, Help, eyre::eyre};

pub fn get_player_interfaces(conn: &Connection) -> Result<Vec<String>> {
    let proxy = conn.with_proxy("org.freedesktop.DBus", "/", Duration::from_millis(5000));
    let (names,): (Vec<String>,) = proxy
        .method_call("org.freedesktop.DBus", "ListNames", ())
        .note("Failed to list DBus names")?;

    Ok(names
        .iter()
        .filter(|name| name.starts_with("org.mpris.MediaPlayer2"))
        .map(|str| str.clone())
        .collect())
}

pub fn get_most_relevant_player(conn: &Connection, players: &Vec<String>) -> Result<String> {
    for player in players {
        let proxy = conn.with_proxy(player, "/org/mpris/MediaPlayer2", Duration::from_secs(1));

        // Either "Playing" or "Paused"
        let status: String = proxy
            .get("org.mpris.MediaPlayer2.Player", "PlaybackStatus")
            .with_note(|| format!("Failed to get playback status of player: {}", player))?;

        if status == "Playing" {
            return Ok(player.clone());
        }
    }

    // No player is currently playing, get the last relevant one.
    match get_saved_player() {
        Ok(player) => match player_exists(conn, &player)? {
            true => return Ok(player),
            false => {}
        },
        Err(e) => match e {
            GetSavedPlayerError::NotFound => {}
            _ => return Err(e.into()),
        },
    };

    players
        .get(0)
        .ok_or_else(|| eyre!("No players found"))
        .cloned()
}

pub fn player_exists(conn: &Connection, player: &str) -> Result<bool> {
    Ok(get_player_interfaces(conn)?.contains(&player.to_string()))
}

pub fn get_config_dir() -> Result<PathBuf> {
    let mut config = dirs::config_dir().expect("No config directory");
    config.push("control-music");

    // Create if it doesn't exist
    match std::fs::metadata(&config) {
        Ok(..) => {}
        Err(e) => match e.kind() {
            std::io::ErrorKind::NotFound => fs::create_dir(&config)?,
            _ => return Err(e.into()),
        },
    }

    Ok(config)
}

#[derive(thiserror::Error, Debug)]
pub enum GetSavedPlayerError {
    #[error(transparent)]
    Other(#[from] color_eyre::Report),

    #[error(transparent)]
    IOError(#[from] io::Error),

    #[error("Saved player file not found")]
    NotFound,
}

pub fn get_saved_player() -> Result<String, GetSavedPlayerError> {
    let mut config_dir = get_config_dir().note("Failed to get config directory")?;
    config_dir.push("relevant_player");
    let save_file = config_dir;

    Ok(match fs::read_to_string(&save_file) {
        Ok(player) => player,
        Err(e) => match e.kind() {
            io::ErrorKind::NotFound => return Err(GetSavedPlayerError::NotFound),
            _ => return Err(e.into()),
        },
    })
}

pub fn save_relevant_player(player: &String) -> Result<()> {
    let mut config_dir = get_config_dir().note("Failed to get config directory")?;
    config_dir.push("relevant_player");
    let save_file = config_dir;

    fs::write(save_file, player).note("Failed to write to file")?;
    Ok(())
}

