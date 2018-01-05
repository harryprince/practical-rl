if !isdefined(:gym) include("../base.jl") end

import MXNet
import POMDPs: Solver

type DeepCrossentropyPolicySolver <: Solver
    epochs::Int64
    n_samples::Int64
    percentile::Float64
    max_frame_iterations::Int64
    nnet_spec::Vector{Int64}
    print_every_n::Int64
end

DeepCrossentropyPolicySolver(epochs = 100, n_samples = 100, percentile = 0.5; max_frame_iterations = 100, nnet_spec = [24, 48], print_every_n = 10) =
    DeepCrossentropyPolicySolver(epochs, n_samples, percentile, max_frame_iterations, nnet_spec, print_every_n)

function solve(solver::DeepCrossentropyPolicySolver, pomdp::MDP; verbose = true)

    policy = DeepCrossentropyPolicy(pomdp; nnet_spec = solver.nnet_spec)
    optimizer = mx.ADAM()

    for i=1:solver.epochs

        # batch_states  = [] # a list of lists of states in each session

        batch_states  = zeros(Float64, n_states(pomdp), solver.n_samples * solver.max_frame_iterations) # a list of lists of states in each session
        batch_actions = zeros(Int64, solver.n_samples * solver.max_frame_iterations) # a list of lists of actions in each session
        batch_rewards_states = zeros(Float64, solver.n_samples * solver.max_frame_iterations)
        batch_rewards = Float64[] # a list of floats - total rewards at each session

        batch_records_index = 0

        for j=1:solver.n_samples

            if verbose && (j == 1 || j % solver.print_every_n == 0)
                println("Epoch: $i, Episode: $j")
            end

            session_states, session_actions, session_reward = run_experiment(pomdp, policy; max_frame_iterations = solver.max_frame_iterations, keep_history = true)

            index_start = batch_records_index + 1
            index_end = batch_records_index + size(session_states)[2]

            batch_states[:, index_start:index_end] = session_states
            batch_actions[index_start:index_end] = session_actions
            batch_rewards_states[index_start:index_end] = session_reward
            append!(batch_rewards, session_reward)

            batch_records_index = index_end
        end

        # Identify threshold which filters out best performing games
        reward_threshold = quantile(batch_rewards, solver.percentile);
        reward_valid_indices = batch_rewards_states .> reward_threshold;
        #
        # Create a filtered view to best peforming games

        # filtered_states  = view(batch_states, :, reward_valid_indices);
        # filtered_actions = view(batch_actions, reward_valid_indices);

        filtered_states  = batch_states[:, reward_valid_indices];
        filtered_actions = batch_actions[reward_valid_indices];

        if length(filtered_actions) > 0
            dataprovider = mx.ArrayDataProvider(:data => filtered_states, :label => filtered_actions)
            mx.fit(policy.net, optimizer, dataprovider, n_epoch = 1, callbacks = [mx.speedometer()])
        end

        println("Sum score: $(sum(batch_rewards)), Max score: $(maximum(batch_rewards)), Mean score: $(round(mean(batch_rewards), 2)), Median score: $(median(batch_rewards))")

        #
        # # Create a new policy matrix which has identical structure and smoothing value
        # policy_values = zeros(policy.action_map) + smoothing;
        # for ep in 1:sum(reward_valid_indices)
        #     map(x -> policy_values[filtered_actions[ep][x] + 1, filtered_states[ep][x] + 1] += 1 , 1:length(filtered_actions[ep]));
        # end
        #
        # policy_values = policy_values ./ sum(policy_values, 1)
        # policy = CrossentropyPolicy(pomdp, policy_values, Int64(mean(batch_rewards)))

    end

    return policy

end
