with this_season as (
select *
from player_seasons
where season = 1997
)
, last_season as (
select *
from players_mine
where current_season = 1996
)
insert into players_mine
select 
	coalesce(ts.player_name,ls.player_name) as player_name,
	coalesce(ts.height,ls.height) as height,
	coalesce(ts.college,ls.college) as college,
	coalesce(ts.draft_year,ls.draft_year) as draft_year,
	coalesce(ts.draft_round,ls.draft_round) as draft_round,
	coalesce(ts.draft_number,ls.draft_number) as draft_number,
	case
		when ls.seasons is null 
			then array[row(ts.season, ts.pts, ts.reb, ts.ast)::season_stats]
		when ls.seasons is not null and ts.season is not null
			then ls.seasons || array[row(ts.season, ts.pts, ts.reb, ts.ast)::season_stats]
		when ls.seasons is not null and ts.season is null
			then ls.seasons
		else array[]::season_stats[]
	end as seasons,
	case 
		when ts.season is not null 
			then (case
				when ts.pts > 20 then 'star'
				when ts.pts > 15 then 'good'
				when ts.pts > 10 then 'average'
				else 'bad'
			end)::scoring_class
		else ls.scoring_class
	end as scoring_class,
	case 
		when ts.season is not null then 0
		else (ls.current_season + 1) - (seasons[cardinality(seasons)]::season_stats).season
	end as years_since_last_active,
	case when ts.season is not null then true else false end as is_active,
	1997 as current_season
from last_season ls
full outer join this_season ts
	on ts.player_name = ls.player_name