insert into players_mine
select 
	player_name,
	height,
	college,
	draft_year,
	draft_round,
	draft_number,
	array[row(season, pts, ast, reb)::season_stats] as seasons,
	(case
		when pts > 20 then 'star'
		when pts > 15 then 'good'
		when pts > 10 then 'average'
		else 'bad'
	end)::scoring_class as scoring_class,
	0 as years_since_last_active,
	true as is_active,
	season as current_season
from player_seasons
where season = 1996