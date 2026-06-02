# Task 1 — Endoscopy MILP (OMPR)

# Packages
library(ompr)
library(ompr.roi)
library(ROI)
library(dplyr)
library(tidyr)
library(ggplot2)
library(ROI.plugin.highs)
library(knitr)
library(kableExtra)

# 1) Indices
# Defines the room and week sets used throughout the model.

# Room and week index sets.
R_rooms <- 10
W_weeks <- 26
rooms <- 1:R_rooms
weeks <- 1:W_weeks

# 2) Parameters
# Stores weekly demand, clinician availability, and room-specific
# capacity and cost inputs.

# Weekly demand and clinician availability.
P_diag  <- c(230,235,225,230,240,245,280,295,300,
             285,240,235,230,225,230,235,240,245,
             250,245,240,235,230,230,235,230)

P_thera <- c(145,145,150,150,155,160,168,176,182,
             188,190,192,188,195,187,182,178,172,
             168,165,162,158,155,152,150,148)

C_w <- c(520,515,525,520,530,525,490,480,485,500,
         510,515,520,525,530,525,520,480,470,475,
         500,510,515,520,525,530)

# Room groups.
small_rooms  <- c(1,2,3)
medium_rooms <- c(4,5,6,7)
large_rooms  <- c(8,9,10)

# Capacity and cost by room type.
B_diag  <- rep(NA, R_rooms)
B_thera <- rep(NA, R_rooms)
A_r     <- rep(NA, R_rooms)
S_r     <- rep(NA, R_rooms)

B_diag[small_rooms]  <-  60; B_thera[small_rooms]  <-  30; A_r[small_rooms]  <- 180; S_r[small_rooms]  <- 15000
B_diag[medium_rooms] <- 120; B_thera[medium_rooms] <-  60; A_r[medium_rooms] <- 200; S_r[medium_rooms] <- 20000
B_diag[large_rooms]  <- 180; B_thera[large_rooms]  <- 120; A_r[large_rooms]  <- 220; S_r[large_rooms]  <- 25000

# Parameter values by room (r).
print(data.frame(r=rooms, B_diag, B_thera, A_r, S_r))

# 3) Model
# Formulates the MILP by defining decision variables, the objective
# function, and the constraints for allocation, demand and setup.

model <- MIPModel() %>%
  
  # Binary variables for room configuration in each week.
  add_variable(x_diag[r,w], r = rooms, w = weeks, type = "binary") %>%
  add_variable(x_thera[r,w], r = rooms, w = weeks, type = "binary") %>%
  
  # Binary setup variable when a room becomes active.
  add_variable(y[r,w], r = rooms, w = weeks, type = "binary") %>%
  
  # Continuous variables for scheduled diagnostic and therapeutic hours.
  add_variable(d[r,w], r = rooms, w = weeks, lb = 0) %>%
  add_variable(t[r,w], r = rooms, w = weeks, lb = 0) %>%
  
  # Objective function: minimise allocation and setup cost.
  set_objective(
    sum_expr(
      A_r[r] * B_diag[r]  * x_diag[r,w] +
        A_r[r] * B_thera[r] * x_thera[r,w] +
        S_r[r] * y[r,w],
      r = rooms, w = weeks
    ),
    "min") %>%
  
  # (C1) Each room can be in at most one mode each week.
  add_constraint(x_diag[r,w] + x_thera[r,w] <= 1, r = rooms, w = weeks) %>%
  
  # (C2) Total diagnostic hours must meet weekly diagnostic demand.
  add_constraint(sum_expr(d[r,w], r = rooms) == P_diag[w], w = weeks) %>%
  
  # (C3) Total therapeutic hours must meet weekly therapeutic demand.
  add_constraint(sum_expr(t[r,w], r = rooms) == P_thera[w], w = weeks) %>%
  
  # (C4) Total scheduled hours must stay within clinician availability.
  add_constraint(sum_expr(d[r,w] + t[r,w], r = rooms) <= C_w[w], w = weeks) %>%
  
  # (C5) Therapeutic hours only allowed in therapeutic rooms.
  add_constraint(t[r,w] <= B_thera[r] * x_thera[r,w], r = rooms, w = weeks) %>%
  
  # (C6) Total room hours limited by the selected weekly configuration.
  # If a room is unused, no hours can be assigned to it.
  add_constraint(
    d[r,w] + t[r,w] <= B_diag[r] * x_diag[r,w] + B_thera[r] * x_thera[r,w],
    r = rooms, w = weeks) %>%
  
  # (C7) In week 1, setup applies if a room is used.
  add_constraint(y[r,1] == x_diag[r,1] + x_thera[r,1], r = rooms) %>%
  
  # (C8) Setup occurs when a room changes from unused to used.
  add_constraint(
    y[r,w] >= (x_diag[r,w] + x_thera[r,w]) - (x_diag[r,w-1] + x_thera[r,w-1]),
    r = rooms, w = 2:W_weeks) %>%
  
  # (C9) Setup can only happen if the room is active in that week.
  add_constraint(
    y[r,w] <= x_diag[r,w] + x_thera[r,w],
    r = rooms, w = 2:W_weeks) %>%
  
  # (C10) No setup if the room was already active in the previous week.
  add_constraint(
    y[r,w] <= 1 - (x_diag[r,w-1] + x_thera[r,w-1]),
    r = rooms, w = 2:W_weeks)

# 4) Solution
# Solves the optimisation model and reports the optimal objective value.

# Solve the MILP using HiGHS.
result <- solve_model(model,
                      with_ROI(solver = "highs", verbose = TRUE))

# Report solver status and objective value.
print(result$status)
cat("Objective value (min cost): ", objective_value(result), "\n")

# 5) Extract solution
# Converts the optimisation output into structured tables
# for validation, analysis and reporting.

# 5.1 Extract solution values for each decision variable
x_diag_sol  <- get_solution(result, x_diag[r,w])  %>% rename(x_diag = value)
x_thera_sol <- get_solution(result, x_thera[r,w]) %>% rename(x_thera = value)
y_sol       <- get_solution(result, y[r,w])       %>% rename(y = value)
d_sol       <- get_solution(result, d[r,w])       %>% rename(d_hours = value)
t_sol       <- get_solution(result, t[r,w])       %>% rename(t_hours = value)

# 5.2 Build a room-week results table

# This block was refined with help from ChatGPT.
# I adapted it to fit this model's variables, room profiles and cost calculations.

sol_rw <- x_diag_sol %>%
  left_join(x_thera_sol, by = c("r","w")) %>%
  left_join(y_sol,       by = c("r","w")) %>%
  left_join(d_sol,       by = c("r","w")) %>%
  left_join(t_sol,       by = c("r","w")) %>%
  mutate(
    # Clean binary values
    x_diag  = as.integer(x_diag  > 0.5),
    x_thera = as.integer(x_thera > 0.5),
    y       = as.integer(y       > 0.5),
    
    # Assign room mode
    mode = case_when(
      x_diag  == 1 ~ "Diagnostic",
      x_thera == 1 ~ "Therapeutic",
      TRUE         ~ "Unavailable"),
    
    used = as.integer(mode != "Unavailable"),
    
    # Add room profile
    profile = case_when(
      r %in% small_rooms  ~ "Small",
      r %in% medium_rooms ~ "Medium",
      r %in% large_rooms  ~ "Large"),
    
    # Calculate weekly room-level costs
    alloc_cost = A_r[r] * (B_diag[r] * x_diag + B_thera[r] * x_thera),
    setup_cost = S_r[r] * y,
    cost_rw    = alloc_cost + setup_cost)

# 5.3 Weekly summary of demand, capacity and cost
weekly_matrix <- sol_rw %>%
  group_by(w) %>%
  summarise(
    D_scheduled = sum(d_hours),
    T_scheduled = sum(t_hours),
    Total_hours = sum(d_hours + t_hours),
    
    D_demand      = P_diag[first(w)],
    T_demand      = P_thera[first(w)],
    Clinician_cap = C_w[first(w)],
    
    Rooms_used  = sum(used),
    Small_used  = sum(used == 1 & profile == "Small"),
    Medium_used = sum(used == 1 & profile == "Medium"),
    Large_used  = sum(used == 1 & profile == "Large"),
    
    Allocation_cost_week = sum(alloc_cost),
    Setup_cost_week      = sum(setup_cost),
    Cost_week            = sum(cost_rw),
    
    D_met        = abs(D_scheduled - D_demand) < 1e-6,
    T_met        = abs(T_scheduled - T_demand) < 1e-6,
    Clinician_ok = Total_hours <= Clinician_cap + 1e-6,
    
    .groups = "drop") %>%
  arrange(w)

# Room-level output table by week.

Room_table <- sol_rw %>%
  mutate(
    Total_Hours = d_hours + t_hours,
    
    Room_Type = case_when(
      mode == "Diagnostic"  ~ "Diagnostic",
      mode == "Therapeutic" ~ "Therapeutic",
      TRUE                  ~ "Unused"),
    
    Demand_Diagnostic  = P_diag[w],
    Demand_Therapeutic = P_thera[w],
    Clinician_Hours    = C_w[w]
  ) %>%
  select(
    Week = w,
    Room = r,
    Room_Type,
    Diagnostic_Hours = d_hours,
    Therapeutic_Hours = t_hours,
    Total_Hours,
    Demand_Diagnostic,
    Demand_Therapeutic,
    Clinician_Hours) %>%
  arrange(Week, Room)

View(Room_table)
View(weekly_matrix)

# Report minimum total cost and validate it against the weekly breakdown.
cat("Objective value (minimum total cost):", objective_value(result), "\n")
cat("Validation check - weekly cost total:", sum(weekly_matrix$Cost_week), "\n")

# 6) Final report outputs
# Produces the tables and figures used to present and interpret
# the optimal solution in the report.

# Some plotting syntax here was adjusted with help from ChatGPT.
# The chart choices, interpretation and final output selection are my own.

# 6.1 Plot settings
# Theme and colour settings chosen to ensure visual consistency
# and clear distinction between chart elements and variables.

diag_col    <- "#1f77b4"
thera_col   <- "#ff7f0e"
unavail_col <- "#ECECEC"
alloc_col   <- "#5B6C7D"
setup_col   <- "#B97A67"
small_col   <- "#6FA8DC"
medium_col  <- "#93C47D"
large_col   <- "#D99694"

theme_model <- theme_minimal(base_size = 13) +
  theme(
    panel.grid = element_blank(),
    axis.line = element_line(color = "black"),
    legend.position = "top",
    panel.background = element_rect(fill = "white", colour = NA),
    plot.background  = element_rect(fill = "white", colour = NA)
  )

# 6.2 Table 3: Overall Solution Statistics
# Summarises the main solution statistics.

summary_stats <- tibble(
  Total_Cost          = objective_value(result),
  Average_Weekly_Cost = mean(weekly_matrix$Cost_week),
  Total_Setups        = sum(sol_rw$y),
  Average_Rooms_Used  = mean(weekly_matrix$Rooms_used)
) %>%
  mutate(across(where(is.numeric), round, 2))

kable(
  summary_stats,
  caption = "Overall Solution Statistics") %>%
  kable_styling(
    full_width = FALSE,
    bootstrap_options = c("striped", "hover"))

# 6.3 Figure 1: Room Configuration by Week
# Shows each room's weekly diagnostic, therapeutic or unused status.

ggplot(sol_rw, aes(x = w, y = factor(r), fill = mode)) +
  geom_tile(width = 0.95, height = 0.95, colour = "white", linewidth = 0.3) +
  scale_fill_manual(values = c(
    Diagnostic  = diag_col,
    Therapeutic = thera_col,
    Unavailable = unavail_col)) +
  scale_x_continuous(breaks = seq(1, 26, 2)) +
  labs(
    title = "Room Configuration by Week",
    x = "Week",
    y = "Room",
    fill = NULL) +
  theme_model

# ggsave("room_configuration.png", width = 8.2, height = 4.8, dpi = 300)

# 6.4 Figure 2: Weekly Bay Hours Available by Configuration
# Compares weekly diagnostic and therapeutic capacity by room configuration.

weekly_capacity <- sol_rw %>%
  group_by(w) %>%
  summarise(
    Diagnostic_capacity  = sum(B_diag[r] * x_diag),
    Therapeutic_capacity = sum(B_thera[r] * x_thera),
    Total_capacity       = Diagnostic_capacity + Therapeutic_capacity,
    .groups = "drop")

ggplot(
  weekly_capacity %>%
    select(w, Diagnostic_capacity, Therapeutic_capacity) %>%
    pivot_longer(
      cols = c(Diagnostic_capacity, Therapeutic_capacity),
      names_to = "Configuration",
      values_to = "Capacity"
    ) %>%
    mutate(
      Configuration = recode(
        Configuration,
        Diagnostic_capacity  = "Diagnostic",
        Therapeutic_capacity = "Therapeutic")),
  aes(x = factor(w), y = Capacity, fill = Configuration)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c(
    Diagnostic  = diag_col,
    Therapeutic = thera_col)) +
  scale_x_discrete(breaks = seq(1, 26, 2)) +
  labs(
    title = "Weekly Bay Hours Available by Configuration",
    x = "Week",
    y = "Bay Hours Available",
    fill = NULL) +
  theme_model

# ggsave("weekly_bay_hours_by_configuration.png", width = 8.2, height = 4.8, dpi = 300)

# 6.5 Figure 3: Weekly Rooms Used by Size
# Shows the number of small, medium and large rooms used each week.

rooms_used_size <- sol_rw %>%
  group_by(w) %>%
  summarise(
    Small  = sum(used == 1 & profile == "Small"),
    Medium = sum(used == 1 & profile == "Medium"),
    Large  = sum(used == 1 & profile == "Large"),
    .groups = "drop") %>%
  pivot_longer(
    cols = c(Small, Medium, Large),
    names_to = "Room Size",
    values_to = "Rooms Used") %>%
  mutate(
    `Room Size` = factor(`Room Size`, levels = c("Small", "Medium", "Large")))

ggplot(rooms_used_size, aes(x = factor(w), y = `Rooms Used`, fill = `Room Size`)) +
  geom_col(width = 0.8, colour = "white", linewidth = 0.25) +
  scale_fill_manual(values = c(
    Small  = small_col,
    Medium = medium_col,
    Large  = large_col)) +
  scale_x_discrete(breaks = seq(1, 26, 2)) +
  scale_y_continuous(
    breaks = 0:8,
    limits = c(0, 8),
    expand = c(0, 0)) +
  labs(
    title = "Weekly Rooms Used by Size",
    x = "Week",
    y = "Number of Rooms Used",
    fill = NULL) +
  theme_model

# ggsave("weekly_rooms_used_by_size.png", width = 8.2, height = 4.8, dpi = 300)

# 6.6 Figure 4: Weekly Cost Composition
# Breaks weekly cost into allocation and setup components.

cost_plot_data <- weekly_matrix %>%
  select(w, Allocation_cost_week, Setup_cost_week) %>%
  rename(
    Allocation = Allocation_cost_week,
    Setup      = Setup_cost_week) %>%
  pivot_longer(
    cols = c(Allocation, Setup),
    names_to = "Cost Type",
    values_to = "Cost")

ggplot(cost_plot_data, aes(x = factor(w), y = Cost, fill = `Cost Type`)) +
  geom_col(width = 0.8) +
  scale_fill_manual(values = c(
    Allocation = alloc_col,
    Setup      = setup_col)) +
  scale_x_discrete(breaks = seq(1, 26, 2)) +
  labs(
    title = "Weekly Cost Composition",
    x = "Week",
    y = "Cost",
    fill = NULL) +
  theme_model

# ggsave("weekly_cost_composition.png", width = 8.2, height = 4.8, dpi = 300)

# 6.7 Table 4: Weekly Cost Breakdown
# Reports weekly allocation, setup and total cost values.

weekly_cost_breakdown <- weekly_matrix %>%
  transmute(
    Week = as.character(w),
    `Allocation Cost` = round(Allocation_cost_week, 2),
    `Setup Cost`      = round(Setup_cost_week, 2),
    `Total Cost`      = round(Cost_week, 2)
  )

weekly_cost_breakdown_total <- weekly_cost_breakdown %>%
  bind_rows(
    summarise(
      .,
      Week = "Total",
      `Allocation Cost` = round(sum(`Allocation Cost`), 2),
      `Setup Cost`      = round(sum(`Setup Cost`), 2),
      `Total Cost`      = round(sum(`Total Cost`), 2)))

kable(
  weekly_cost_breakdown_total,
  caption = "Weekly Cost Breakdown") %>%
  kable_styling(
    full_width = FALSE,
    font_size = 9)

# 6.8 Table 5: Weekly Feasibility Check
# Confirms that weekly diagnostic and therapeutic demand is met
# and that total scheduled hours remain within clinician capacity.

feasibility_small <- weekly_matrix %>%
  transmute(
    Week = w,
    `Diag Demand`    = round(D_demand, 1),
    `Diag Sched`     = round(D_scheduled, 1),
    `Thera Demand`   = round(T_demand, 1),
    `Thera Sched`    = round(T_scheduled, 1),
    `Clinician Cap`  = round(Clinician_cap, 1),
    `Total Hours`    = round(Total_hours, 1),
    `Demand Met`     = ifelse(D_met & T_met, "Yes", "No"),
    `Clinician OK`   = ifelse(Clinician_ok, "Yes", "No"),
    `Rooms Used`     = Rooms_used)

kable(
  feasibility_small,
  caption = "Weekly Feasibility Check") %>%
  kable_styling(
    full_width = FALSE,
    font_size = 8)
