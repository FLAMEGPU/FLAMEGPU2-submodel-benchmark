#include <iostream>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <array>

#include "flamegpu/flamegpu.h"

// Agent state variables
#define AGENT_STATUS_UNOCCUPIED 0
#define AGENT_STATUS_OCCUPIED 1
#define AGENT_STATUS_MOVEMENT_REQUESTED 2
#define AGENT_STATUS_MOVEMENT_UNRESOLVED 3

// Growback variables
#define ENV_SUGAR_GROWBACK_RATE 1
#define ENV_SUGAR_MAX_CAPACITY 4
#define MIN_HOTSPOT_DISTANCE 20

#define MIN_INIT_AGENT_SUAGR_WEALTH 5
#define MAX_INIT_AGENT_SUAGR_WEALTH 25

#define MIN_INIT_METABOLISM 1
#define MAX_INIT_METABOLISM 4
#define PROBABILITY_OF_OCCUPATION 0.17f


// Visualisation mode (0=occupied/move status, 1=occupied/sugar/level)
#define VIS_MODE 1

#define BENCHMARK_STEPS 1000


FLAMEGPU_AGENT_FUNCTION(metabolise_and_growback, flamegpu::MessageNone, flamegpu::MessageNone) {
    int sugar_level = FLAMEGPU->getVariable<int>("sugar_level");
    int env_sugar_level = FLAMEGPU->getVariable<int>("env_sugar_level");
    int env_max_sugar_level = FLAMEGPU->getVariable<int>("env_max_sugar_level");
    int status = FLAMEGPU->getVariable<int>("status");
    // metabolise if occupied
    if (status == AGENT_STATUS_OCCUPIED || status == AGENT_STATUS_MOVEMENT_UNRESOLVED) {
        // store any sugar present in the cell
        if (env_sugar_level > 0) {
            sugar_level += env_sugar_level;
            // Occupied cells are marked as -1 sugar.
            env_sugar_level = -1;
        }

        // metabolise
        sugar_level -= FLAMEGPU->getVariable<int>("metabolism");

        // check if agent dies
        if (sugar_level == 0) {
            status = AGENT_STATUS_UNOCCUPIED;
            FLAMEGPU->setVariable<int>("agent_id", -1);
            sugar_level = 0;
            FLAMEGPU->setVariable<int>("metabolism", 0);
        }
    }

    // growback if unoccupied
    if (status == AGENT_STATUS_UNOCCUPIED) {
        env_sugar_level += ENV_SUGAR_GROWBACK_RATE;
        if (env_sugar_level > env_max_sugar_level) {
            env_sugar_level = env_max_sugar_level;
        }
    }

    // set all active agents to unresolved as they may now want to move
    if (status == AGENT_STATUS_OCCUPIED) {
        status = AGENT_STATUS_MOVEMENT_UNRESOLVED;
    }
    FLAMEGPU->setVariable<int>("sugar_level", sugar_level);
    FLAMEGPU->setVariable<int>("env_sugar_level", env_sugar_level);
    FLAMEGPU->setVariable<int>("status", status);

    return flamegpu::ALIVE;
}
FLAMEGPU_AGENT_FUNCTION(output_cell_status, flamegpu::MessageNone, flamegpu::MessageArray2D) {
    unsigned int agent_x = FLAMEGPU->getVariable<unsigned int, 2>("pos", 0);
    unsigned int agent_y = FLAMEGPU->getVariable<unsigned int, 2>("pos", 1);
    FLAMEGPU->message_out.setVariable("location_id", FLAMEGPU->getID());
    FLAMEGPU->message_out.setVariable("status", FLAMEGPU->getVariable<int>("status"));
    FLAMEGPU->message_out.setVariable("env_sugar_level", FLAMEGPU->getVariable<int>("env_sugar_level"));
    FLAMEGPU->message_out.setIndex(agent_x, agent_y);
    return flamegpu::ALIVE;
}
FLAMEGPU_AGENT_FUNCTION(movement_request, flamegpu::MessageArray2D, flamegpu::MessageArray2D) {
    int best_sugar_level = -1;
    float best_sugar_random = -1;
    flamegpu::id_t best_location_id = flamegpu::ID_NOT_SET;

    // if occupied then look for empty cells {
    // find the best location to move to (ensure we don't just pick first cell with max value)
    int status = FLAMEGPU->getVariable<int>("status");

    unsigned int agent_x = FLAMEGPU->getVariable<unsigned int, 2>("pos", 0);
    unsigned int agent_y = FLAMEGPU->getVariable<unsigned int, 2>("pos", 1);

    // if occupied then look for empty cells
    if (status == AGENT_STATUS_MOVEMENT_UNRESOLVED) {
        for (auto current_message : FLAMEGPU->message_in.wrap(agent_x, agent_y)) {
            // if location is unoccupied then check for empty locations
            if (current_message.getVariable<int>("status") == AGENT_STATUS_UNOCCUPIED) {
                // if the sugar level at current location is better than currently stored then update
                int message_env_sugar_level = current_message.getVariable<int>("env_sugar_level");
                float message_priority = FLAMEGPU->random.uniform<float>();
                if ((message_env_sugar_level > best_sugar_level) ||
                    (message_env_sugar_level == best_sugar_level && message_priority > best_sugar_random)) {
                    best_sugar_level = message_env_sugar_level;
                    best_sugar_random = message_priority;
                    best_location_id = current_message.getVariable<flamegpu::id_t>("location_id");
                }
            }
        }

        // if the agent has found a better location to move to then update its state
        // if there is a better location to move to then state indicates a movement request
        status = best_location_id != flamegpu::ID_NOT_SET ? AGENT_STATUS_MOVEMENT_REQUESTED : AGENT_STATUS_OCCUPIED;
        FLAMEGPU->setVariable<int>("status", status);
    }

    // add a movement request
    FLAMEGPU->message_out.setVariable<int>("agent_id", FLAMEGPU->getVariable<int>("agent_id"));
    FLAMEGPU->message_out.setVariable<flamegpu::id_t>("location_id", best_location_id);
    FLAMEGPU->message_out.setVariable<int>("sugar_level", FLAMEGPU->getVariable<int>("sugar_level"));
    FLAMEGPU->message_out.setVariable<int>("metabolism", FLAMEGPU->getVariable<int>("metabolism"));
    FLAMEGPU->message_out.setIndex(agent_x, agent_y);

    return flamegpu::ALIVE;
}
FLAMEGPU_AGENT_FUNCTION(movement_response, flamegpu::MessageArray2D, flamegpu::MessageArray2D) {
    int best_request_id = -1;
    float best_request_priority = -1;
    int best_request_sugar_level = -1;
    int best_request_metabolism = -1;

    int status = FLAMEGPU->getVariable<int>("status");
    const flamegpu::id_t location_id = FLAMEGPU->getID();
    const unsigned int agent_x = FLAMEGPU->getVariable<unsigned int, 2>("pos", 0);
    const unsigned int agent_y = FLAMEGPU->getVariable<unsigned int, 2>("pos", 1);

    for (auto current_message : FLAMEGPU->message_in.wrap(agent_x, agent_y)) {
        // if the location is unoccupied then check for agents requesting to move here
        if (status == AGENT_STATUS_UNOCCUPIED) {
            // check if request is to move to this location
            if (current_message.getVariable<flamegpu::id_t>("location_id") == location_id) {
                // check the priority and maintain the best ranked agent
                float message_priority = FLAMEGPU->random.uniform<float>();
                if (message_priority > best_request_priority) {
                    best_request_id = current_message.getVariable<int>("agent_id");
                    best_request_priority = message_priority;
                }
            }
        }
    }

    // if the location is unoccupied and an agent wants to move here then do so and send a response
    if ((status == AGENT_STATUS_UNOCCUPIED) && (best_request_id >= 0)) {
        FLAMEGPU->setVariable<int>("status", AGENT_STATUS_OCCUPIED);
        // move the agent to here and consume the cell's sugar
        best_request_sugar_level += FLAMEGPU->getVariable<int>("env_sugar_level");
        FLAMEGPU->setVariable<int>("agent_id", best_request_id);
        FLAMEGPU->setVariable<int>("sugar_level", best_request_sugar_level);
        FLAMEGPU->setVariable<int>("metabolism", best_request_metabolism);
        FLAMEGPU->setVariable<int>("env_sugar_level", -1);
    }

    // add a movement response
    FLAMEGPU->message_out.setVariable<int>("agent_id", best_request_id);
    FLAMEGPU->message_out.setIndex(agent_x, agent_y);

    return flamegpu::ALIVE;
}
FLAMEGPU_AGENT_FUNCTION(movement_transaction, flamegpu::MessageArray2D, flamegpu::MessageNone) {
    int status = FLAMEGPU->getVariable<int>("status");
    int agent_id = FLAMEGPU->getVariable<int>("agent_id");
    unsigned int agent_x = FLAMEGPU->getVariable<unsigned int, 2>("pos", 0);
    unsigned int agent_y = FLAMEGPU->getVariable<unsigned int, 2>("pos", 1);

    for (auto current_message : FLAMEGPU->message_in.wrap(agent_x, agent_y)) {
        // if location contains an agent wanting to move then look for responses allowing relocation
        if (status == AGENT_STATUS_MOVEMENT_REQUESTED) {  // if the movement response request came from this location
            if (current_message.getVariable<int>("agent_id") == agent_id) {
                // remove the agent and reset agent specific variables as it has now moved
                status = AGENT_STATUS_UNOCCUPIED;
                FLAMEGPU->setVariable<int>("agent_id", -1);
                FLAMEGPU->setVariable<int>("sugar_level", 0);
                FLAMEGPU->setVariable<int>("metabolism", 0);
                FLAMEGPU->setVariable<int>("env_sugar_level", 0);
            }
        }
    }

    // if request has not been responded to then agent is unresolved
    if (status == AGENT_STATUS_MOVEMENT_REQUESTED) {
        status = AGENT_STATUS_MOVEMENT_UNRESOLVED;
    }

    FLAMEGPU->setVariable<int>("status", status);

    return flamegpu::ALIVE;
}
FLAMEGPU_EXIT_CONDITION(MovementExitCondition) {
    static unsigned int iterations = 0;
    iterations++;

    // Max iterations 9
    if (iterations < 9) {
        // Agent movements still unresolved
        if (FLAMEGPU->agent("agent").count("status", AGENT_STATUS_MOVEMENT_UNRESOLVED)) {
            return flamegpu::CONTINUE;
        }
    }

    iterations = 0;
    return flamegpu::EXIT;
}
/**
 * Construct the common components of agent shared between both parent and submodel
 */
flamegpu::AgentDescription& makeCoreAgent(flamegpu::ModelDescription& model) {
    flamegpu::AgentDescription& agent = model.newAgent("agent");
    agent.newVariable<unsigned int, 2>("pos");
    agent.newVariable<int>("agent_id");
    agent.newVariable<int>("status");
    // agent specific variables
    agent.newVariable<int>("sugar_level");
    agent.newVariable<int>("metabolism");
    // environment specific var
    agent.newVariable<int>("env_sugar_level");
    agent.newVariable<int>("env_max_sugar_level");
#ifdef VISUALISATION
    // Redundant seperate floating point position vars for vis
    agent.newVariable<float>("x");
    agent.newVariable<float>("y");
#endif
    return agent;
}


bool hotspot_distance_check(const std::vector<std::array<unsigned int, 2>>& sugar_hotspots, const std::array<unsigned int, 2>& hs, const unsigned int gridWidth) {
    bool pass = true;
    for (auto& h : sugar_hotspots) {
        // calculate the distance between spots
        unsigned int dx = std::abs(static_cast<int>(std::get<0>(hs)) - static_cast<int>(std::get<0>(h)));
        unsigned int dy = std::abs(static_cast<int>(std::get<1>(hs)) - static_cast<int>(std::get<1>(h)));
        // if distance in a dimension is greater than half grid width then points are closer via wrapping
        if (dx > (gridWidth >>1))
            dx = gridWidth - dx;
        if (dy > (gridWidth >> 1))
            dy = gridWidth - dy;

        if (std::sqrt((pow(dx, 2.0f) + pow(dy, 2.0f))) < static_cast<float>(MIN_HOTSPOT_DISTANCE) )
            pass = false;
    }
    return pass;
}


typedef struct Experiment {
    Experiment(std::string title,
        unsigned int initialGridWidth, unsigned int finalGridWidth, unsigned int gridWidthIncrement,
        unsigned int repetitions,
        unsigned int steps) {
        this->title = title;
        this->initialGridWidth = initialGridWidth;
        this->finalGridWidth = finalGridWidth;
        this->gridWidthIncrement = gridWidthIncrement;
        this->repetitions = repetitions;
        this->steps = steps;
    }
    std::string title;
    unsigned int initialGridWidth, finalGridWidth, gridWidthIncrement;
    unsigned int repetitions;
    unsigned int steps;
} Experiment;

int main(int argc, const char** argv) {
    // For visualisation define only a single execution othger wise describe benchmark experiment
#ifdef VISUALISATION
    Experiment smallPopBruteForce("sub_model", 256, 256, 64, 1, 0);
#else
     // Experiment smallPopBruteForce("sub_model", 64, 256, 64, 2, BENCHMARK_STEPS);
     Experiment smallPopBruteForce("sub_model", 64, 4096, 64, 50, BENCHMARK_STEPS);
#endif

    std::vector<Experiment> experiments = { smallPopBruteForce };
    for (Experiment experiment : experiments) {
        std::cout << std::endl << "Starting experiment: " << experiment.title << std::endl;

        // Pandas logging
        std::string csvFileName = experiment.title + ".csv";
        std::ofstream csv(csvFileName, std::ios::app);
        csv << "repetition,grid_width,pop_size,ms_step_mean" << std::endl;

        // number of repitions of experiment
        for (unsigned int repetition = 0; repetition < experiment.repetitions; repetition++) {
            // increment grid width
            for (unsigned int gridWidth = experiment.initialGridWidth; gridWidth <= experiment.finalGridWidth; gridWidth += experiment.gridWidthIncrement) {
                unsigned int popSize = gridWidth * gridWidth;

                std::cout << "Staring run with popSize: " << popSize << ", gridthWidth: " << gridWidth << std::endl;

                flamegpu::ModelDescription submodel("Movement_model");
                {  // Define sub model for conflict resolution
                    /**
                     * Messages
                     */
                    {   // cell_status message
                        flamegpu::MessageArray2D::Description& message = submodel.newMessage<flamegpu::MessageArray2D>("cell_status");
                        message.newVariable<flamegpu::id_t>("location_id");
                        message.newVariable<int>("status");
                        message.newVariable<int>("env_sugar_level");
                        message.setDimensions(gridWidth, gridWidth);
                    }
                    {   // movement_request message
                        flamegpu::MessageArray2D::Description& message = submodel.newMessage<flamegpu::MessageArray2D>("movement_request");
                        message.newVariable<int>("agent_id");
                        message.newVariable<flamegpu::id_t>("location_id");
                        message.newVariable<int>("sugar_level");
                        message.newVariable<int>("metabolism");
                        message.setDimensions(gridWidth, gridWidth);
                    }
                    {   // movement_response message
                        flamegpu::MessageArray2D::Description& message = submodel.newMessage<flamegpu::MessageArray2D>("movement_response");
                        message.newVariable<flamegpu::id_t>("location_id");
                        message.newVariable<int>("agent_id");
                        message.setDimensions(gridWidth, gridWidth);
                    }
                    /**
                     * Agents
                     */
                    {
                        flamegpu::AgentDescription& agent = makeCoreAgent(submodel);
                        auto& fn_output_cell_status = agent.newFunction("output_cell_status", output_cell_status);
                        {
                            fn_output_cell_status.setMessageOutput("cell_status");
                        }
                        auto& fn_movement_request = agent.newFunction("movement_request", movement_request);
                        {
                            fn_movement_request.setMessageInput("cell_status");
                            fn_movement_request.setMessageOutput("movement_request");
                        }
                        auto& fn_movement_response = agent.newFunction("movement_response", movement_response);
                        {
                            fn_movement_response.setMessageInput("movement_request");
                            fn_movement_response.setMessageOutput("movement_response");
                        }
                        auto& fn_movement_transaction = agent.newFunction("movement_transaction", movement_transaction);
                        {
                            fn_movement_transaction.setMessageInput("movement_response");
                        }
                    }

                    /**
                     * Globals
                     */
                    {
                        // flamegpu::EnvironmentDescription  &env = model.Environment();
                    }

                    /**
                     * Control flow
                     */
                    {   // Layer #1
                        flamegpu::LayerDescription& layer = submodel.newLayer();
                        layer.addAgentFunction(output_cell_status);
                    }
                    {   // Layer #2
                        flamegpu::LayerDescription& layer = submodel.newLayer();
                        layer.addAgentFunction(movement_request);
                    }
                    {   // Layer #3
                        flamegpu::LayerDescription& layer = submodel.newLayer();
                        layer.addAgentFunction(movement_response);
                    }
                    {   // Layer #4
                        flamegpu::LayerDescription& layer = submodel.newLayer();
                        layer.addAgentFunction(movement_transaction);
                    }
                    submodel.addExitCondition(MovementExitCondition);
                }

                flamegpu::ModelDescription model("Sugarscape_example");

                /**
                 * Agents
                 */
                {   // Per cell agent
                    flamegpu::AgentDescription& agent = makeCoreAgent(model);
                    // Functions
                    agent.newFunction("metabolise_and_growback", metabolise_and_growback);
                }

                /**
                 * Submodels
                 */
                flamegpu::SubModelDescription& movement_sub = model.newSubModel("movement_conflict_resolution_model", submodel);
                {
                    movement_sub.bindAgent("agent", "agent", true, true);
                }

                /**
                 * Globals
                 */
                {
                    // flamegpu::EnvironmentDescription  &env = model.Environment();
                }

                /**
                 * Control flow
                 */
                {   // Layer #1
                    flamegpu::LayerDescription& layer = model.newLayer();
                    layer.addAgentFunction(metabolise_and_growback);
                }
                {   // Layer #2
                    flamegpu::LayerDescription& layer = model.newLayer();
                    layer.addSubModel(movement_sub);
                }
                NVTX_POP();

                /**
                 * Create Model Runner
                 */
                flamegpu::CUDASimulation  cudaSimulation(model);


                /**
                 * Create visualisation
                 * @note FLAMEGPU2 doesn't currently have proper support for discrete/2d visualisations
                 */
#ifdef VISUALISATION
                flamegpu::visualiser::ModelVis& visualisation = cudaSimulation.getVisualisation();
                {
                    visualisation.setSimulationSpeed(2);
                    visualisation.setInitialCameraLocation(gridWidth / 2.0f, gridWidth / 2.0f, 225.0f);
                    visualisation.setInitialCameraTarget(gridWidth / 2.0f, gridWidth / 2.0f, 0.0f);
                    visualisation.setCameraSpeed(0.001f * gridWidth);
                    visualisation.setViewClips(0.1f, 5000);
                    auto& agt = visualisation.addAgent("agent");
                    // Position vars are named x, y, z; so they are used by default
                    agt.setModel(flamegpu::visualiser::Stock::Models::CUBE);  // 5 unwanted faces!
                    agt.setModelScale(1.0f);
#if VIS_MODE == 0
                    flamegpu::visualiser::DiscreteColor<int> cell_colors = flamegpu::visualiser::DiscreteColor<int>("status", flamegpu::visualiser::Color{ "#666" });
                    cell_colors[AGENT_STATUS_UNOCCUPIED] = flamegpu::visualiser::Stock::Colors::RED;
                    cell_colors[AGENT_STATUS_OCCUPIED] = flamegpu::visualiser::Stock::Colors::GREEN;
                    cell_colors[AGENT_STATUS_MOVEMENT_REQUESTED] = flamegpu::visualiser::Stock::Colors::BLUE;  // Not possible, only occurs inside the submodel
                    cell_colors[AGENT_STATUS_MOVEMENT_UNRESOLVED] = flamegpu::visualiser::Stock::Colors::WHITE;
                    agt.setColor(cell_colors);
#else
                    flamegpu::visualiser::DiscreteColor<int> cell_colors = flamegpu::visualiser::DiscreteColor<int>("env_sugar_level", flamegpu::visualiser::Stock::Palettes::Viridis(ENV_SUGAR_MAX_CAPACITY + 1), flamegpu::visualiser::Color{ "#f00" });
                    agt.setColor(cell_colors);
#endif
                }
                visualisation.activate();
#endif

                /**
                 * Initialisation
                 */
                cudaSimulation.initialise(argc, argv);
                if (cudaSimulation.getSimulationConfig().input_file.empty()) {
                    std::default_random_engine rng;
                    // Pre init, decide the sugar hotspots
                    std::vector<std::array<unsigned int, 2>> sugar_hotspots;
                    {
                        std::uniform_int_distribution<unsigned int> width_dist(0, gridWidth - 1);
                        std::uniform_int_distribution<unsigned int> height_dist(0, gridWidth - 1);
                        // There are a number of hotspots which create an average denisty based on that of the original model
                        unsigned int num_hotspots = (2 * gridWidth * gridWidth) / (49 * 49);
                        for (unsigned int h = 0; h < num_hotspots; h++) {
                            // create random position for new hotspot
                            std::array<unsigned int, 2> hs = { width_dist(rng), height_dist(rng) };
                            // recursively ensure that the a random position is not within an euclidean distance of 10
                            unsigned int attempts = 0;
                            while (!hotspot_distance_check(sugar_hotspots, hs, gridWidth)) {
                                hs = { width_dist(rng), height_dist(rng) };
                                attempts++;
                                // give up if no position found after 100 attempts
                                if (attempts == 100) {
                                    std::cout << "Warning: Maximum attempts reached creating unique location for sugar hotspot." << std::endl;
                                    break;
                                }
                            }
                            // add hostpot after it has passed the distance checks
                            sugar_hotspots.push_back(hs);
                        }
                    }


                    // Currently population has not been init, so generate an agent population on the fly
                    const unsigned int CELL_COUNT = gridWidth * gridWidth;
                    std::uniform_real_distribution<float> normal(0, 1);
                    std::uniform_int_distribution<int> agent_sugar_dist(MIN_INIT_AGENT_SUAGR_WEALTH, MAX_INIT_AGENT_SUAGR_WEALTH);
                    std::uniform_int_distribution<int> agent_metabolism_dist(MIN_INIT_METABOLISM, MAX_INIT_METABOLISM);
                    unsigned int i = 0;
                    unsigned int agent_id = 0;
                    flamegpu::AgentVector init_pop(model.Agent("agent"), CELL_COUNT);
                    for (unsigned int x = 0; x < gridWidth; ++x) {
                        for (unsigned int y = 0; y < gridWidth; ++y) {
                            flamegpu::AgentVector::Agent instance = init_pop[i++];
                            instance.setVariable<unsigned int, 2>("pos", { x, y });
                            // 10% chance of cell holding an agent
                            if (normal(rng) < PROBABILITY_OF_OCCUPATION) {
                                instance.setVariable<int>("agent_id", agent_id++);
                                instance.setVariable<int>("status", AGENT_STATUS_OCCUPIED);
                                instance.setVariable<int>("sugar_level", agent_sugar_dist(rng));
                                instance.setVariable<int>("metabolism", agent_metabolism_dist(rng));
                            } else {
                                instance.setVariable<int>("agent_id", -1);
                                instance.setVariable<int>("status", AGENT_STATUS_UNOCCUPIED);
                                instance.setVariable<int>("sugar_level", 0);
                                instance.setVariable<int>("metabolism", 0);
                            }
                            // environment specific var
                            unsigned int env_sugar_lvl = 0;
                            const int hotspot_core_size = 5.0f;
                            for (auto& hs : sugar_hotspots) {
                                // Workout the highest sugar lvl from a nearby hotspot
                                int hs_x = static_cast<int>(std::get<0>(hs));
                                int hs_y = static_cast<int>(std::get<1>(hs));
                                // distance to hotspot
                                float hs_dist = static_cast<float>(sqrt(pow(hs_x - static_cast<int>(x), 2.0f) + pow(hs_y - static_cast<int>(y), 2.0f)));

                                // four bands of sugar with increasing radius of 5
                                env_sugar_lvl += 4 - std::min<int>(4, static_cast<int>(floor(hs_dist / hotspot_core_size)));
                            }
                            env_sugar_lvl = env_sugar_lvl > ENV_SUGAR_MAX_CAPACITY ? ENV_SUGAR_MAX_CAPACITY : env_sugar_lvl;
                            instance.setVariable<int>("env_max_sugar_level", env_sugar_lvl);  // All cells begin at their local max sugar
                            instance.setVariable<int>("env_sugar_level", env_sugar_lvl);
#ifdef VISUALISATION
                            // Redundant separate floating point position vars for vis
                            instance.setVariable<float>("x", static_cast<float>(x));
                            instance.setVariable<float>("y", static_cast<float>(y));
#endif
                        }
                    }
                    cudaSimulation.setPopulationData(init_pop);
                }

                /**
                 * Execution
                 */
                cudaSimulation.simulate();
#ifdef VISUALISATION
                visualisation.join();
#else
                const auto runTime = cudaSimulation.getElapsedTimeSimulation();
                const double averageStepTime = runTime / static_cast<float>(BENCHMARK_STEPS);
                // log timings to csv (repetition,grid_width,pop_size,ms_step_mean)
                csv << repetition << "," << gridWidth  << "," << popSize << "," << averageStepTime << std::endl;
#endif
            }
        }
    }

    return 0;
}
