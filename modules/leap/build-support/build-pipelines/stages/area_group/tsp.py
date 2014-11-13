##
## Traveling salesman using simulated annealing, derived from:
##
##    http://www.psychicorigami.com/2007/06/28/tackling-the-travelling-salesman-problem-simmulated-annealing/
##
##

##
## Pass a list of coordinate tuples to tsp() and get back an ordered list
## of node IDs to visit.
##

import random
import sys
import getopt
import math

## We always want the same result, but don't want to affect other random
## sequences.
pvtRandom = random.Random()


## ========================================================================
## 
##  Simulated annealing.
##
## ========================================================================

def P(prev_score,next_score,temperature):
    if next_score > prev_score:
        return 1.0
    else:
        return math.exp( -abs(next_score-prev_score)/temperature )

class ObjectiveFunction:
    '''
    Class to wrap an objective function and keep track of the best solution
    evaluated.
    '''
    def __init__(self,objective_function):
        self.objective_function=objective_function
        self.best=None
        self.best_score=None
    
    def __call__(self,solution):
        score=self.objective_function(solution)
        if self.best is None or score > self.best_score:
            self.best_score=score
            self.best=solution
        return score

def kirkpatrick_cooling(start_temp,alpha):
    T=start_temp
    while True:
        yield T
        T=alpha*T

def anneal(init_function,move_operator,objective_function,max_evaluations,start_temp,alpha):
    # wrap the objective function (so we record the best)
    objective_function=ObjectiveFunction(objective_function)
    
    current=init_function()
    current_score=objective_function(current)
    num_evaluations=1
    
    cooling_schedule=kirkpatrick_cooling(start_temp,alpha)
    
    for temperature in cooling_schedule:
        done = False
        # examine moves around our current position
        for next in move_operator(current):
            if num_evaluations >= max_evaluations:
                done=True
                break
            
            next_score=objective_function(next)
            num_evaluations+=1
            
            # probablistically accept this solution
            # always accepting better solutions
            p=P(current_score,next_score,temperature)
            if pvtRandom.random() < p:
                current=next
                current_score=next_score
                break
        # see if completely finished
        if done: break
    
    best_score=objective_function.best_score
    best=objective_function.best
    return (num_evaluations,best_score,best)



## ========================================================================
## 
##  Traveling salesman.
##
## ========================================================================

def rand_seq(size):
    '''
    Generates values in random order equivalent to using shuffle in random,
    without generating all values at once
    '''
    values=range(size)
    for i in xrange(size):
        # pick a random index into remaining values
        j=i+int(pvtRandom.random()*(size-i))
        # swap the values
        values[j],values[i]=values[i],values[j]
        # return the swapped value
        yield values[i] 


def all_pairs(size):
    '''
    Generates all i,j pairs for i,j from 0-size
    '''
    for i in rand_seq(size):
        for j in rand_seq(size):
            yield (i,j)


def reversed_sections(tour):
    '''
    Generator to return all possible variations where the section between
    two cities are swapped.
    '''
    for i,j in all_pairs(len(tour)):
        if i != j:
            copy=tour[:]
            if i < j:
                copy[i:j+1]=reversed(tour[i:j+1])
            else:
                copy[i+1:]=reversed(tour[:j])
                copy[:j]=reversed(tour[i+1:])
            if copy != tour: # no point returning the same tour
                yield copy


def cartesian_matrix(coords):
    '''
    Create a distance matrix for the city coords that uses straight line
    distance.
    '''
    matrix={}
    for i,(x1,y1) in enumerate(coords):
        for j,(x2,y2) in enumerate(coords):
            dx,dy=x1-x2,y1-y2
            dist=math.sqrt(dx*dx + dy*dy)
            matrix[i,j]=dist
    return matrix


def tour_length(matrix,tour):
    '''
    Total up the total length of the tour based on the distance matrix.
    '''
    total=0
    num_cities=len(tour)
    for i in range(num_cities):
        j=(i+1)%num_cities
        city_i=tour[i]
        city_j=tour[j]
        total+=matrix[city_i,city_j]
    return total


def init_random_tour(tour_length):
    tour=range(tour_length)
    pvtRandom.shuffle(tour)
    return tour


def run_anneal(init_function,objective_function,max_iterations,start_temp,alpha):
    iterations,score,best=anneal(init_function,reversed_sections,objective_function,max_iterations,start_temp,alpha)
    return iterations,score,best


def travelingSalesman(coords,
                      max_iterations = 25000,
                      start_temp = 10,
                      alpha = 0.99995,
                      verbose = False):
    '''
    Solve the traveling salesman problem given a list of coordinates.  Returns
    the ordered path as a list of node IDs.
    '''
    # Always return the same result.
    pvtRandom.seed(1)

    init_function=lambda: init_random_tour(len(coords))
    matrix=cartesian_matrix(coords)
    objective_function=lambda tour: -tour_length(matrix,tour)
    
    iterations,score,best=run_anneal(init_function,objective_function,max_iterations,start_temp,alpha)

    # output results
    if (verbose):
        print "Iterations: " + str(iterations)
        print "Score:      " + str(score)

    return best


if __name__ == "__main__":
    ##
    ## Solve a simple problem:
    ##
    ##  0  1  2
    ##     3  4
    ##  5  6  7
    ##
    coords = [(0, 0), (1, 0), (2, 0),
                      (1, 1), (2, 1),
              (0, 2), (1, 2), (2, 2)]
    
    path = travelingSalesman(coords, verbose=True)
    print "Path:       " + str(path)
