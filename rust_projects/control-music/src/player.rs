use serde::Serialize;
use std::{collections::HashMap, fmt::Display};

use color_eyre::{eyre::eyre, Result};
use dbus::{
    arg::{RefArg, Variant},
    blocking::{stdintf::org_freedesktop_dbus::Properties, Connection, Proxy},
};

#[derive(Debug)]
pub enum PlaybackStatus {
    Playing,
    Paused,
}

impl Display for PlaybackStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{}",
            match self {
                PlaybackStatus::Playing => "Playing",
                PlaybackStatus::Paused => "Paused",
            }
        )
    }
}

#[derive(thiserror::Error, Debug)]
#[error("Invalid playback status: {0}")]
pub struct InvalidPlaybackStatus(String);

impl TryFrom<String> for PlaybackStatus {
    type Error = InvalidPlaybackStatus;

    fn try_from(value: String) -> std::result::Result<Self, Self::Error> {
        match value.as_str() {
            "Playing" => Ok(PlaybackStatus::Playing),
            "Paused" => Ok(PlaybackStatus::Paused),
            _ => Err(InvalidPlaybackStatus(value.to_string())),
        }
    }
}

#[derive(Debug, Serialize)]
pub struct MediaMetadata {
    pub title: Option<String>,
    pub artists: Option<Vec<String>>,
    pub length: i64,
}

impl Display for MediaMetadata {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "Title: {}", self.title.clone().unwrap_or("-".to_string()))?;
        writeln!(f, "Artists: {}", self.artists.clone().map(|artists| artists.join(", ")).unwrap_or("-".to_string()))?;
        writeln!(f, "Length: {}", self.length)
    }
}

pub struct Player<'a> {
    proxy: Proxy<'a, &'a Connection>,
}

impl<'a> Player<'a> {
    pub fn new(proxy: Proxy<'a, &'a Connection>) -> Self {
        Self { proxy }
    }

    pub fn play(&self) -> Result<()> {
        Ok(self.proxy.method_call::<(), (), &str, &str>(
            "org.mpris.MediaPlayer2.Player",
            "Play",
            (),
        )?)
    }

    pub fn pause(&self) -> Result<()> {
        Ok(self.proxy.method_call::<(), (), &str, &str>(
            "org.mpris.MediaPlayer2.Player",
            "Pause",
            (),
        )?)
    }

    pub fn play_pause(&self) -> Result<()> {
        Ok(self.proxy.method_call::<(), (), &str, &str>(
            "org.mpris.MediaPlayer2.Player",
            "PlayPause",
            (),
        )?)
    }

    pub fn next(&self) -> Result<()> {
        Ok(self.proxy.method_call::<(), (), &str, &str>(
            "org.mpris.MediaPlayer2.Player",
            "Next",
            (),
        )?)
    }

    pub fn prev(&self) -> Result<()> {
        Ok(self.proxy.method_call::<(), (), &str, &str>(
            "org.mpris.MediaPlayer2.Player",
            "Previous",
            (),
        )?)
    }

    pub fn get_status(&self) -> Result<PlaybackStatus> {
        Ok(self
            .proxy
            .get::<String>("org.mpris.MediaPlayer2.Player", "PlaybackStatus")?
            .try_into()?)
    }

    pub fn get_position(&self) -> Result<i64> {
        Ok(self
            .proxy
            .get("org.mpris.MediaPlayer2.Player", "Position")?)
    }

    pub fn get_length(&self) -> Result<i64> {
        let map = self.get_metadata_map()?;

        let variant = map
            .get("mpris:length")
            .ok_or_else(|| eyre!("Failed to get length"))?;

        // Unfortunately due to differing implementations we have to do this.
        match variant.as_i64() {
            Some(value) => Ok(value),
            None => match variant.as_u64() {
                Some(value) => Ok(value.try_into().unwrap()),
                None => return Err(eyre!("Failed to parse length")),
            },
        }
    }

    fn get_metadata_map(&self) -> Result<HashMap<String, Variant<Box<dyn RefArg>>>> {
        Ok(self
            .proxy
            .get("org.mpris.MediaPlayer2.Player", "Metadata")?)
    }

    fn get_artists_from_variant(&self, variant: &Variant<Box<dyn RefArg>>) -> Option<Vec<String>> {
        let mut artists: Vec<String> = vec![];

        // For some reason the dbus crate returns an iterator over iterators of artists
        let artist_iter_iter = match variant.as_iter() {
            Some(x) => x,
            None => return None,
        };

        for artist_iter in artist_iter_iter {
            let artist_iter = match artist_iter.as_iter() {
                Some(x) => x,
                None => return None,
            };

            for artist in artist_iter {
                match artist.as_str() {
                    Some(artist) => artists.push(artist.to_string()),
                    None => return None,
                }
            }
        }

        Some(artists)
    }

    pub fn get_metadata(&self) -> Result<MediaMetadata> {
        let map = self.get_metadata_map()?;

        let title: Option<String> = map
            .get("xesam:title")
            .and_then(|title| title.as_str().map(|s| s.to_string()));

        let artists: Option<Vec<String>> = match map.get("xesam:artist") {
            Some(artists) => self.get_artists_from_variant(artists),
            None => None,
        };

        let length = self.get_length()?;

        Ok(MediaMetadata {
            title,
            artists,
            length,
        })
    }

    // I don't think it's necessary to include serde and its dependencies to serialize this.
    pub fn get_all_data_json(&self) -> Result<String> {
        let metadata = self.get_metadata()?;

        Ok(serde_json::to_string(&metadata)?)
    }
}
